{
  lib,
  buildNpmPackage,
  nodejs_24,
  makeWrapper,
  ffmpeg-full,
  callPackage,
}:

let
  prisma-engines = callPackage ./prisma-engines.nix { };
in

buildNpmPackage {
  pname = "zipp-server";
  version = "1.0.0";

  src = lib.fileset.toSource {
    root = ../server;
    fileset = lib.fileset.difference ../server/. (
      lib.fileset.unions (map lib.fileset.maybeMissing [
        ../server/.env
        ../server/.env.example
        ../server/flake.nix
        ../server/flake.lock
      ])
    );
  };

  npmDepsHash = "sha256-l4rXfOzHN9NqLAUIfu58FWM499VEnlcYQpKAFOmfEgY=";

  nodejs = nodejs_24;
  nativeBuildInputs = [ makeWrapper ];

  # Skip npm postinstall (it runs `prisma generate` which tries to
  # download engine binaries).  We run it manually below with the
  # Nix-built schema engine instead.
  npmFlags = [ "--ignore-scripts" ];

  # Prisma needs DATABASE_URL for schema parsing (no actual connection).
  env.DATABASE_URL = "postgresql://build:build@localhost:5432/build";

  dontNpmBuild = true;

  postBuild = ''
    # Run prisma generate with the Nix-built schema engine
    export PRISMA_SCHEMA_ENGINE_BINARY="${prisma-engines}/bin/schema-engine"
    export PRISMA_FMT_BINARY="${prisma-engines}/bin/prisma-fmt"
    npx prisma generate
  '';

  postInstall = ''
    makeWrapper ${nodejs_24}/bin/node $out/bin/zipp-server \
      --add-flags "$out/lib/node_modules/zipp-server/src/server.js" \
      --prefix PATH : ${lib.makeBinPath [ ffmpeg-full nodejs_24 ]}
  '';

  meta = {
    description = "Zipp messaging server";
    mainProgram = "zipp-server";
    license = lib.licenses.gpl3Plus;
  };
}
