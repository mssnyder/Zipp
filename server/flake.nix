{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      prisma-engines = pkgs.callPackage ../nix/prisma-engines.nix { };
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        name = "zipp-server";
        buildInputs = with pkgs; [
          nodejs_24
          openssl
          prisma-engines
        ];
        shellHook = ''
          export PRISMA_SCHEMA_ENGINE_BINARY="${prisma-engines}/bin/schema-engine"
          export PRISMA_FMT_BINARY="${prisma-engines}/bin/prisma-fmt"
        '';
      };
    };
}
