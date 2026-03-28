# Fetches the pre-built Flutter web client from a GitHub Release.
#
# After a new release is created by GitHub Actions, update the tag and hash:
#   nix-prefetch-url --unpack https://github.com/mssnyder/Zipp/releases/download/TAG/zipp-web.tar.gz
{
  lib,
  stdenv,
  fetchzip,
  clientRelease ? "client-20260328-888c4376",
}:

let
  src = fetchzip {
    url = "https://github.com/mssnyder/Zipp/releases/download/${clientRelease}/zipp-web.tar.gz";
    hash = "sha256-Q86xQxQ3RM+fTK+j3YDIdu2K9CFA1s17BzuyAbHnVJo=";
    stripRoot = false;
  };
in

stdenv.mkDerivation {
  pname = "zipp-web";
  version = clientRelease;

  inherit src;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r * $out/
    runHook postInstall
  '';

  meta = {
    description = "Zipp web client (Flutter web build)";
    license = lib.licenses.gpl3Plus;
  };
}
