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
      default = throw "Missing owner";
      description = "The owner of the repository";
    };

    repo = lib.mkOption {
      type = lib.types.str;
      default = throw "Missing repo";
      description = "The name of the repository";
    };
  };

  config = lib.mkIf cfg.enable {
    # see `gh help environment` to see potential env vars
    env.GH_REPO = "${cfg.owner}/${cfg.repo}";
    packages = [ pkgs.gh ];
  };
}
