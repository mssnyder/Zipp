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
        default = self.packages.${system}.server;
      };

      # NixOS module for the server service + nginx reverse proxy.
      # The client desktop package is in nix/client.nix but requires a
      # local Flutter build (can't be built in a Nix sandbox), so it's
      # called directly via callPackage in the consuming NixOS config.
      nixosModules.default = import ./nix/module.nix self.packages.${system}.server;
    };
}
