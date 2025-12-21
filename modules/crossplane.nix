{
  pkgs,
  config,
  lib,
  ...
}:

let
  cfg = config.crossplane;
in
{
  options.crossplane = {
    enable = lib.mkEnableOption "crossplane";
  };

  config = lib.mkIf cfg.enable {
    packages = [ pkgs.crossplane-cli ];

    scripts.validate-database.exec = ./scripts/validate-database.sh;
  };
}
