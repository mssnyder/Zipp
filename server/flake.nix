{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      prisma-engines = pkgs.rustPlatform.buildRustPackage rec {
        pname = "prisma-engines";
        version = "7.0.1";

        src = pkgs.fetchFromGitHub {
          owner = "prisma";
          repo = "prisma-engines";
          rev = version;
          hash = "sha256-+8k+M2+WySR2CeywYlhU/jd3av/4UeUoEOlO/qHUk5o=";
        };

        cargoHash = "sha256-n83hJfSlvuaoBb3w9Rk8+q2emjGCoPDHhFdoVzhf4sM=";

        OPENSSL_NO_VENDOR = 1;

        nativeBuildInputs = [ pkgs.pkg-config ];
        buildInputs = [ pkgs.openssl ];

        preBuild = ''
          export OPENSSL_DIR=${pkgs.lib.getDev pkgs.openssl}
          export OPENSSL_LIB_DIR=${pkgs.lib.getLib pkgs.openssl}/lib
          export PROTOC=${pkgs.protobuf}/bin/protoc
          export PROTOC_INCLUDE="${pkgs.protobuf}/include";
          export SQLITE_MAX_VARIABLE_NUMBER=250000
          export SQLITE_MAX_EXPR_DEPTH=10000
          export GIT_HASH=0000000000000000000000000000000000000000
        '';

        cargoBuildFlags = [ "-p" "schema-engine-cli" "-p" "prisma-fmt" ];
        doCheck = false;
      };
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
