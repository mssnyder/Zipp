# Packages a pre-built Flutter Linux desktop bundle.
#
# Since Flutter can't be built reproducibly inside a Nix sandbox,
# this derivation wraps a pre-built bundle.  Build it first:
#
#   cd client && nix develop && flutter build linux --release
#
# Then in your NixOS config, call this with the local build path
# and server URL:
#
#   (pkgs.callPackage "${inputs.zipp}/nix/client.nix" {
#     serverUrl = "https://messaging.example.com";
#   })
{
  src ? ../client/bundle,
  serverUrl,
  lib,
  stdenv,
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

stdenv.mkDerivation {
  pname = "zipp";
  version = "0.1.0";

  inherit src;

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

    cp -r lib data zipp $out/opt/zipp/

    # Wrap the binary to inject the server URL at runtime.
    makeWrapper $out/opt/zipp/zipp $out/bin/zipp \
      --set ZIPP_SERVER_URL "${serverUrl}"

    # Install icon
    for size in 16 32 48 64 128 256 512 1024; do
      dir=$out/share/icons/hicolor/''${size}x''${size}/apps
      mkdir -p "$dir"
      cp data/flutter_assets/assets/images/icon.png "$dir/zipp.png"
    done

    runHook postInstall
  '';

  # Tell autoPatchelf to also look in the bundled lib/ for Flutter's own .so files
  appendRunpaths = [ "$ORIGIN" "$ORIGIN/lib" ];
  autoPatchelfIgnoreMissingDeps = false;

  meta = {
    description = "Zipp – Private E2E encrypted messaging (desktop client)";
    mainProgram = "zipp";
  };
}
