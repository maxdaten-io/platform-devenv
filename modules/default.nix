# platform-devenv modules
# Import all available modules for easy consumption
{
  imports = [
    ./crossplane.nix
    ./google-cloud.nix
    ./github.nix
    ./gws.nix
    ./krmc.nix
  ];
}
