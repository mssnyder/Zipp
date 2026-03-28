# Fetches the pre-built Flutter web client from a GitHub Release.
#
# After a new release is created by GitHub Actions, update the tag and hash:
#   nix-prefetch-url --unpack https://github.com/mssnyder/Zipp/releases/download/TAG/zipp-web.tar.gz
{
  lib,
  stdenv,
  fetchurl,
  clientRelease ? "client-20260328-00000000",
}:

let
  src = fetchurl {
    url = "https://github.com/mssnyder/Zipp/releases/download/${clientRelease}/zipp-web.tar.gz";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };
in

stdenv.mkDerivation {
  pname = "zipp-web";
  version = clientRelease;

  inherit src;
  sourceRoot = ".";
  unpackCmd = "mkdir src && tar -xzf $curSrc -C src";

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r src/* $out/
    runHook postInstall
  '';

  meta = {
    description = "Zipp web client (Flutter web build)";
    license = lib.licenses.gpl3Plus;
  };
}
