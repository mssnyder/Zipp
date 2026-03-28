# Fetches the pre-built Flutter Linux desktop client from a GitHub Release
# and wraps it with the server URL injected at runtime.
#
# After a new release is created by GitHub Actions, update the tag and hash:
#   nix-prefetch-url --unpack https://github.com/mssnyder/Zipp/releases/download/TAG/zipp-linux.tar.gz
#
# In your NixOS config:
#   (pkgs.callPackage "${inputs.zipp}/nix/client.nix" {
#     serverUrl = "https://messaging.example.com";
#   })
{
  serverUrl,
  clientRelease ? "client-20260328-00000000",
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  wrapGAppsHook3,
  copyDesktopItems,
  makeDesktopItem,
  gtk3,
  glib,
  cairo,
  pango,
  harfbuzz,
  atk,
  gdk-pixbuf,
  libepoxy,
  fontconfig,
  zlib,
  libsecret,
  xdg-utils,
  libayatana-appindicator,
  libdbusmenu,
  alsa-lib,
  mpv-unwrapped,
}:

let
  src = fetchurl {
    url = "https://github.com/mssnyder/Zipp/releases/download/${clientRelease}/zipp-linux.tar.gz";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };
in

stdenv.mkDerivation {
  pname = "zipp";
  version = clientRelease;

  inherit src;
  sourceRoot = ".";
  unpackCmd = "mkdir src && tar -xzf $curSrc -C src";

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    wrapGAppsHook3
    copyDesktopItems
  ];

  buildInputs = [
    gtk3
    glib
    cairo
    pango
    harfbuzz
    atk
    gdk-pixbuf
    libepoxy
    fontconfig
    zlib
    libsecret
    xdg-utils
    # tray_manager (system tray)
    libayatana-appindicator
    libdbusmenu
    # media_kit (video playback)
    alsa-lib
    mpv-unwrapped
  ];

  desktopItems = [
    (makeDesktopItem {
      name = "zipp";
      desktopName = "Zipp";
      comment = "Private E2E encrypted messaging";
      exec = "zipp";
      icon = "zipp";
      categories = [ "Network" "InstantMessaging" ];
      startupWMClass = "zipp";
    })
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/opt/zipp $out/bin

    cp -r src/lib src/data src/zipp $out/opt/zipp/

    # Wrap the binary to inject the server URL at runtime.
    makeWrapper $out/opt/zipp/zipp $out/bin/zipp \
      --set ZIPP_SERVER_URL "${serverUrl}"

    # Install icon
    for size in 16 32 48 64 128 256 512 1024; do
      dir=$out/share/icons/hicolor/''${size}x''${size}/apps
      mkdir -p "$dir"
      cp src/data/flutter_assets/assets/images/icon.png "$dir/zipp.png"
    done

    runHook postInstall
  '';

  # Tell autoPatchelf to also look in the bundled lib/ for Flutter's own .so files
  appendRunpaths = [ "$ORIGIN" "$ORIGIN/lib" ];
  autoPatchelfIgnoreMissingDeps = false;

  meta = {
    description = "Zipp – Private E2E encrypted messaging (desktop client)";
    mainProgram = "zipp";
    license = lib.licenses.gpl3Plus;
  };
}
