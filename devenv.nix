{
  pkgs,
  lib,
  ...
}:
let

  shellBanner = pkgs.writeShellApplication {
    name = "shell-banner";
    text = ''
      ${pkgs.figlet}/bin/figlet -f slant "$1" | ${pkgs.lolcat}/bin/lolcat
    '';
  };
in
{
  imports = [
    ./modules/default.nix
  ];

  config = {
    languages.nix.enable = true;

    # https://devenv.sh/reference/options/
    packages = [ shellBanner ];
  };

}
