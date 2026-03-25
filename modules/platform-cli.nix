{
  config,
  lib,
  pkgs,
  ...
}:

{
  packages = [
    pkgs.gum
  ];

  scripts.platform-onboard.exec = ./scripts/platform-onboard.sh;
}
