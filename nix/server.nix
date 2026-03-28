{
  lib,
  buildNpmPackage,
  nodejs_24,
  makeWrapper,
  ffmpeg-full,
}:

buildNpmPackage {
  pname = "zipp-server";
  version = "1.0.0";

  src = lib.fileset.toSource {
    root = ../server;
    fileset = lib.fileset.difference ../server/. (
      lib.fileset.unions [
        ../server/.env
        ../server/.env.example
        ../server/flake.nix
        ../server/flake.lock
      ]
    );
  };

  npmDepsHash = "sha256-l4rXfOzHN9NqLAUIfu58FWM499VEnlcYQpKAFOmfEgY=";

  nodejs = nodejs_24;
  nativeBuildInputs = [ makeWrapper ];

  # The postinstall script runs `prisma generate` which creates the
  # JS client code.  Prisma 7.x bundles WASM engines, so no native
  # engine binary is needed for generation or at runtime when using
  # the @prisma/adapter-pg driver adapter.
  dontNpmBuild = true;

  postInstall = ''
    # Create a convenience wrapper that includes ffmpeg for video
    # transcoding and node for any child processes.
    makeWrapper ${nodejs_24}/bin/node $out/bin/zipp-server \
      --add-flags "$out/lib/node_modules/zipp-server/src/server.js" \
      --prefix PATH : ${lib.makeBinPath [ ffmpeg-full nodejs_24 ]}
  '';

  meta = {
    description = "Zipp messaging server";
    mainProgram = "zipp-server";
  };
}
