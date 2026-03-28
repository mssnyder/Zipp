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
        # Desktop client — override serverUrl in your NixOS config:
        #   inputs.zipp.packages.x86_64-linux.client.override {
        #     serverUrl = "https://messaging.example.com";
        #   }
        client = pkgs.callPackage ./nix/client.nix { serverUrl = "https://example.com"; };
        default = self.packages.${system}.client;
      };

      # NixOS module — server service + nginx reverse proxy.
      # After GitHub Actions creates a new client release, update
      # clientRelease here and run: nix flake update
      nixosModules.default = import ./nix/module.nix {
        zipp-server = self.packages.${system}.server;
        zipp-web = self.packages.${system}.web-client;
      };

      # Home Manager module — desktop client with serverUrl as a config option:
      #   imports = [ inputs.zipp.homeManagerModules.default ];
      #   programs.zipp = { enable = true; serverUrl = "https://messaging.example.com"; };
      homeManagerModules.default = import ./nix/hm-module.nix {
        zipp-client = self.packages.${system}.client;
      };
    };
}
