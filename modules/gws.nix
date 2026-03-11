{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.gws;
  configDir = "${config.devenv.state}/gws";
  clientSecretFile = "${configDir}/client_secret.json";

  fetchClientSecretScript = pkgs.writeShellScript "gws-fetch-client-secret.sh" ''
    set -euo pipefail
    mkdir -p ${configDir}

    client_id="$(gcloud secrets versions access latest \
      --secret=gws-oauth-client-id \
      --project=${cfg.projectId})"
    client_secret="$(gcloud secrets versions access latest \
      --secret=gws-oauth-client-secret \
      --project=${cfg.projectId})"

    cat > ${clientSecretFile} <<ENDJSON
    {
      "installed": {
        "client_id": "$client_id",
        "client_secret": "$client_secret",
        "project_id": "${cfg.projectId}",
        "auth_uri": "https://accounts.google.com/o/oauth2/auth",
        "token_uri": "https://oauth2.googleapis.com/token",
        "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
        "redirect_uris": ["http://localhost"]
      }
    }
    ENDJSON
    echo "gws: fetched OAuth client credentials from Secret Manager"
  '';
in
{
  options.gws = {
    enable = lib.mkEnableOption "gws (Google Workspace CLI)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.gws;
      defaultText = "pkgs.gws";
      description = "The package to use for Google Workspace CLI";
    };

    projectId = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "GCP project hosting the OAuth client for Google Workspace CLI";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.projectId != "";
        message = "gws.projectId must be set when gws.enable is true";
      }
    ];

    packages = [ cfg.package ];

    env.GOOGLE_WORKSPACE_CLI_CONFIG_DIR = configDir;
    env.CLOUDSDK_BILLING_QUOTA_PROJECT = cfg.projectId;

    tasks."gws:fetch-credentials" = {
      exec = fetchClientSecretScript;
      before = [ "gws:auth-check" ];
      status = ''
        [ -f ${clientSecretFile} ]
      '';
    };

    tasks."gws:auth-check" = {
      exec = ''
        mkdir -p ${configDir}
        echo "gws: no credentials found — run 'gws auth setup' or 'gws auth login'"
      '';
      before = [ "devenv:enterShell" ];
      status = ''
        [ -f "${configDir}/credentials.json" ] || [ -f "${configDir}/credentials.enc" ]
      '';
    };
  };
}
