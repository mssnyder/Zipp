{
  description = "Zipp – Private E2E encrypted messaging";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      packages.${system} = {
        server = pkgs.callPackage ./nix/server.nix { };
        web-client = pkgs.callPackage ./nix/web-client.nix { };
        default = self.packages.${system}.server;
      };

      # NixOS module for the server service + nginx reverse proxy.
      # The desktop client (nix/client.nix) is called directly via
      # callPackage in the consuming NixOS config with serverUrl set.
      #
      # After GitHub Actions creates a new client release, update
      # clientRelease here and run: nix flake update
      nixosModules.default = import ./nix/module.nix {
        zipp-server = self.packages.${system}.server;
        zipp-web = self.packages.${system}.web-client;
      };
    };
}
