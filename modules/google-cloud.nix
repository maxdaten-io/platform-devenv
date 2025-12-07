{
  pkgs,
  config,
  lib,
  inputs,
  ...
}:

let
  cfg = config.google-cloud;

  stateDirectory = "${config.devenv.state}/google-cloud";
  kubernetesConfig = "${stateDirectory}/kubeconfig.yaml";

  clusterCredentialsEnabled =
    cfg.cluster.getCredentials
    && cfg.cluster.name != ""
    && cfg.cluster.region != ""
    && cfg.projectId != "";

  enableCloudProjectScript = pkgs.writeShellScript "enable-cloud-project.sh" ''
    if [[ -z "${cfg.projectId}" ]]; then
      echo "google-cloud.project is not set" >&2
      exit 1
    fi

    echo "🛎 Enable Google Cloud Project: ${cfg.projectId}"
    gcloud config set project "${cfg.projectId}"

  '';

  getVersions = pkgs.writeShellScript "get-versions.sh" ''
    echo -e "\033[34m=== Cluster Version ===\033[0m"
    kubectl version --output yaml | yq -P
    echo -e "\033[34m=== Flux Version ===\033[0m"
    flux version | yq -P
    echo -e "\033[34m=== Crossplane Version ===\033[0m"
    crossplane version | yq -P
  '';

  getClusterCredentialsScript = pkgs.writeShellScript "get-cluster-credentials.sh" ''
    set -e
    if [[ -z "${cfg.cluster.name}" ]]; then
      echo "google-cloud.cluster.name is not set" >&2
      exit 1
    fi
    if [[ -z "${cfg.cluster.region}" ]]; then
      echo "google-cloud.cluster.region is not set" >&2
      exit 1
    fi
    if [[ -z "${cfg.projectId}" ]]; then
      echo "google-cloud.project is not set" >&2
      exit 1
    fi

    gcloud container clusters get-credentials ${cfg.cluster.name} --region ${cfg.cluster.region} --project ${cfg.cluster.projectId}
    echo -e "\033[34m=== 🟢 Connected to cluster: ${cfg.cluster.name} in ${cfg.cluster.region} ===\033[0m"
    ${lib.optionalString cfg.printVersions ''
      source ${getVersions}
    ''}
  '';
in
{
  options.google-cloud = {
    enable = lib.mkEnableOption "google-cloud";

    sdk-package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.google-cloud-sdk;
      defaultText = "pkgs.google-cloud-sdk";
      description = "The package to use for google-cloud-sdk";
    };

    projectId = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "The default project to use for gcloud commands";
    };

    enableProject = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Automatically set project on shell initialization";
    };

    cluster = {
      projectId = lib.mkOption {
        type = lib.types.str;
        default = cfg.projectId;
        description = "The gke project of the cluster (default: google-cloud.projectId)";
      };
      name = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "The gke cluster name to connect to";
      };
      region = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "region of the cluster";
      };

      getCredentials = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Automatically fetch cluster credentials on shell initialization";
      };
    };

    printVersions = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Print versions of kubectl and crossplane after connecting to the cluster (slows down devenv start).";
    };

    sops.enable = lib.mkEnableOption "Mozilla SOPS for secrets management";
  };

  config = lib.mkIf cfg.enable {
    overlays =
      let
        missing = throw ''
          The gcloud-auth-plugin input is required for google-cloud module.
          Add it to your inputs in devenv.yaml or flake.nix:

          inputs:
            gcloud-auth-plugin:
              url: github:maxdaten-io/gke-gcloud-auth-plugin-nix
        '';
      in
      [ (if inputs ? gcloud-auth-plugin then inputs.gcloud-auth-plugin.overlays.default else missing) ];

    packages =
      with pkgs;
      [
        cfg.sdk-package
        # basic tools
        kubectl
        kustomize
        k9s
        terraformer
        gke-gcloud-auth-plugin

        # extended cluster management tools
        cmctl
        fluxcd
        fluxcd-operator
        crossplane-cli
        istioctl
        kubernetes-helm-wrapped
        telepresence2
      ]
      ++ lib.optionals cfg.sops.enable [
        sops
        kustomize-sops
      ];

    env = lib.mkMerge [
      (lib.mkIf clusterCredentialsEnabled {
        USE_GKE_GCLOUD_AUTH_PLUGIN = "true";
        KUBECONFIG = kubernetesConfig;
        KUBE_CONFIG_PATH = config.env.KUBECONFIG; # For terraform kubernetes provider
      })
      (lib.optionalAttrs (cfg.projectId != "") {
        GOOGLE_CLOUD_PROJECT = cfg.projectId;
      })
    ];

    # Use tasks for shell initialization to provide better control and caching.
    tasks."google-cloud:enable-project" = lib.mkIf (cfg.projectId != "" && cfg.enableProject) {
      exec = ''
        mkdir -p ${stateDirectory}
        source ${enableCloudProjectScript}
        echo -n "${cfg.projectId}" > ${stateDirectory}/project-id
      '';
      before = [ "devenv:enterShell" ];
      status = ''
        # Skip if gcloud is already configured for the desired project
        current="$(gcloud config get-value project 2>/dev/null || true)"
        [ "$current" = "${cfg.projectId}" ]
      '';
    };

    tasks."google-cloud:get-credentials" = lib.mkIf clusterCredentialsEnabled {
      exec = ''
        mkdir -p ${stateDirectory}
        # Persist kubeconfig location
        export KUBECONFIG=${kubernetesConfig}
        # Fetch credentials
        source ${getClusterCredentialsScript}
        echo -n "${cfg.cluster.name}:${cfg.cluster.region}:${cfg.cluster.projectId}" > ${stateDirectory}/cluster.stamp
      '';
      before = [
        "devenv:enterShell"
        "devenv:enterTest"
      ];
      status = ''
        # If stamp matches desired cluster, and KUBECONFIG exists, skip
        [ -f ${stateDirectory}/cluster.stamp ] || exit 1
        [ -f ${kubernetesConfig} ] || exit 1
        [ "$(cat ${stateDirectory}/cluster.stamp)" = "${cfg.cluster.name}:${cfg.cluster.region}:${cfg.cluster.projectId}" ]
      '';
    };

    scripts.get-service-account-credentials.exec = ''
      as=$(kubectl get serviceAccount "$1" --namespace "$2" -o jsonpath='{.secrets[0].name}') && echo "associated secret: $as"
      ca=$(kubectl get secret "$as" --namespace "$2" -o jsonpath='{.data.ca\.crt}') && echo "K8S_CA_BASE64: $ca"
      to=$(kubectl get secret "$as" --namespace "$2" -o jsonpath='{.data.token}'|base64 -d) && echo "K8S_SA_TOKEN: $to"
    '';

    scripts.gcp-costs.exec = ''
      ${./scripts/gcp-costs.sh} "$@"
    '';
  };
}