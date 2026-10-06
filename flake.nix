{
  description = "Nix package and NixOS module for the UUGear Witty Pi 4 software";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "aarch64-linux"
        "armv7l-linux"
        "armv6l-linux"
        "x86_64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        wittypi4 = pkgs.callPackage ./package.nix { };
        default = wittypi4;
      });

      overlays.default = final: prev: {
        wittypi4 = final.callPackage ./package.nix { };
      };

      nixosModules = rec {
        wittypi = import ./module.nix self;
        default = wittypi;
      };

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
