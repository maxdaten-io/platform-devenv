{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.gws;
  configDir = "${config.devenv.state}/gws";
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

    tasks."gws:auth-check" = {
      exec = ''
        mkdir -p ${configDir}
        echo "gws: no credentials found — run 'gws auth setup' or 'gws auth login'"
      '';
      before = [ "devenv:enterShell" ];
      status = ''
        config_dir="${configDir}"
        [ -f "$config_dir/credentials.json" ] || [ -f "$config_dir/credentials.enc" ]
      '';
    };
  };
}
