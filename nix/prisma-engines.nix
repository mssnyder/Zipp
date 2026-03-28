# Builds the Prisma schema engine and prisma-fmt from source.
# These are needed at build time for `prisma generate` and at dev time
# for migrations.  They are NOT needed at runtime when using
# @prisma/adapter-pg (WASM query engine handles that).
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  openssl,
  protobuf,
}:

rustPlatform.buildRustPackage rec {
  pname = "prisma-engines";
  version = "7.0.1";

  src = fetchFromGitHub {
    owner = "prisma";
    repo = "prisma-engines";
    rev = version;
    hash = "sha256-+8k+M2+WySR2CeywYlhU/jd3av/4UeUoEOlO/qHUk5o=";
  };

  cargoHash = "sha256-n83hJfSlvuaoBb3w9Rk8+q2emjGCoPDHhFdoVzhf4sM=";

  OPENSSL_NO_VENDOR = 1;

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ openssl ];

  preBuild = ''
    export OPENSSL_DIR=${lib.getDev openssl}
    export OPENSSL_LIB_DIR=${lib.getLib openssl}/lib
    export PROTOC=${protobuf}/bin/protoc
    export PROTOC_INCLUDE="${protobuf}/include";
    export SQLITE_MAX_VARIABLE_NUMBER=250000
    export SQLITE_MAX_EXPR_DEPTH=10000
    export GIT_HASH=0000000000000000000000000000000000000000
  '';

  cargoBuildFlags = [
    "-p" "schema-engine-cli"
    "-p" "prisma-fmt"
  ];
  doCheck = false;
}
