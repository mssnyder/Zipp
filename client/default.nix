{
  lib,
  stdenv,
  autoPatchelfHook,
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
}:

stdenv.mkDerivation {
  pname = "zipp";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [
    autoPatchelfHook
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

    ln -s $out/opt/zipp/zipp $out/bin/zipp

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
}
