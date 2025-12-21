{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.github;
in
{
  options.github = {
    enable = lib.mkEnableOption "github";

    owner = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "The owner of the repository";
    };

    repo = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "The name of the repository";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.owner != "";
        message = "github.owner must be set when github.enable is true";
      }
      {
        assertion = cfg.repo != "";
        message = "github.repo must be set when github.enable is true";
      }
    ];

    # see `gh help environment` to see potential env vars
    env.GH_REPO = "${cfg.owner}/${cfg.repo}";
    packages = [ pkgs.gh ];
  };
}
