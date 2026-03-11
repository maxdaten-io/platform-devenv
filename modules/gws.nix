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

    # Check if SM secrets are populated
    if ! gcloud secrets versions access latest \
        --secret=gws-oauth-client-id \
        --project=${cfg.projectId} >/dev/null 2>&1; then
      echo ""
      echo "gws: OAuth client credentials not found in Secret Manager."
      echo ""
      echo "To set up:"
      echo "  1. Go to https://console.cloud.google.com/apis/credentials?project=${cfg.projectId}"
      echo "  2. Create an OAuth 2.0 Client ID (type: Desktop app)"
      echo "  3. Store the credentials:"
      echo "     echo -n 'CLIENT_ID' | gcloud secrets versions add gws-oauth-client-id --project=${cfg.projectId} --data-file=-"
      echo "     echo -n 'CLIENT_SECRET' | gcloud secrets versions add gws-oauth-client-secret --project=${cfg.projectId} --data-file=-"
      echo ""
      echo "Or run 'gws auth setup --project ${cfg.projectId}' to create the client interactively,"
      echo "then store the values from the generated client_secret.json into SM."
      exit 0
    fi

    client_id="$(gcloud secrets versions access latest \
      --secret=gws-oauth-client-id \
      --project=${cfg.projectId})"
    client_secret="$(gcloud secrets versions access latest \
      --secret=gws-oauth-client-secret \
      --project=${cfg.projectId})"

    ${pkgs.jq}/bin/jq -n \
      --arg cid "$client_id" \
      --arg csec "$client_secret" \
      --arg pid "${cfg.projectId}" \
      '{installed:{client_id:$cid,client_secret:$csec,project_id:$pid,auth_uri:"https://accounts.google.com/o/oauth2/auth",token_uri:"https://oauth2.googleapis.com/token",auth_provider_x509_cert_url:"https://www.googleapis.com/oauth2/v1/certs",redirect_uris:["http://localhost"]}}' \
      > ${clientSecretFile}
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
      exec = "source ${fetchClientSecretScript}";
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
