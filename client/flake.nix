{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config = {
          android_sdk.accept_license = true;
          allowUnfree = true;
        };
      };

      androidComposition = pkgs.androidenv.composeAndroidPackages {
        cmdLineToolsVersion = "13.0";
        platformVersions = [ "35" ];
        buildToolsVersions = [ "35.0.0" ];
        includeNDK = false;
        includeSystemImages = false;
        includeEmulator = false;
      };

      androidSdk = androidComposition.androidsdk;

      # Minimal mpv dev package for building media_kit_video.
      # Provides headers, libmpv.so, and a self-contained .pc file
      # (no Requires: chain) so pkg-config doesn't chase transitive deps.
      # The actual libmpv used at runtime is bundled by media_kit_libs_linux.
      mpvDev = pkgs.runCommand "mpv-dev-minimal" { } ''
        mkdir -p $out/lib/pkgconfig $out/include

        # Headers
        cp -r ${pkgs.mpv-unwrapped.dev}/include/mpv $out/include/

        # Shared library (for the linker)
        cp -P ${pkgs.mpv-unwrapped}/lib/libmpv.so* $out/lib/

        # Self-contained pkg-config file (no Requires: line)
        cat > $out/lib/pkgconfig/mpv.pc << EOF
        prefix=$out
        libdir=''${prefix}/lib
        includedir=''${prefix}/include

        Name: mpv
        Description: mpv media player client library
        Version: 0.0.0
        Cflags: -I''${includedir}
        Libs: -L''${libdir} -lmpv
        EOF
      '';
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        name = "zipp-client";

        buildInputs = with pkgs; [
          flutter
          androidSdk
          jdk17
          # Compression / System
          xz
          zstd
          zlib
          libdeflate
          # Linux desktop build deps
          libxtst
          libxkbcommon
          gtk3
          pkg-config
          libepoxy
          glib
          libsysprof-capture
          pcre2
          util-linux.dev
          libselinux
          libsepol
          # flutter_secure_storage_linux
          libsecret
          libgcrypt
          libgpg-error
          libthai
          libdatrie
          libxdmcp
          # tray_manager (system tray)
          libayatana-appindicator
          # Image/media
          libwebp
          libpng
          zlib
          libdeflate
          lerc
          # media_kit (video playback)
          alsa-lib
          mpvDev
        ];

        shellHook = ''
          export ANDROID_SDK_ROOT="${androidSdk}/libexec/android-sdk"
          export ANDROID_HOME="$ANDROID_SDK_ROOT"
          export JAVA_HOME="${pkgs.jdk17}"
          export PATH="$ANDROID_SDK_ROOT/cmdline-tools/13.0/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"

          # Flutter config
          export FLUTTER_ROOT="${pkgs.flutter}"
          export PUB_CACHE="$HOME/.pub-cache"

          # Help CMake find ALSA and mpv (needed by media_kit plugins)
          export CMAKE_PREFIX_PATH="${pkgs.alsa-lib.dev}:${pkgs.alsa-lib}:${mpvDev}:''${CMAKE_PREFIX_PATH:-}"

          # Use nix-built libmpv at runtime instead of media_kit_libs_linux's
          # bundled one (which segfaults on NixOS due to wrong RPATHs).
          export LD_LIBRARY_PATH="${mpvDev}/lib:''${LD_LIBRARY_PATH:-}"

          # Suppress benign GTK/ATK noise
          export NO_AT_BRIDGE=1      # Don't try to connect to AT-SPI2 accessibility bus
          export GTK_USE_PORTAL=0    # Don't query xdg-desktop-portal for theme settings

          echo "Zipp Flutter dev shell"
          echo "  flutter --version"
          echo "  flutter pub get"
          echo "  flutter run -d linux"
          echo "  flutter build apk"
          echo "  flutter build linux"
          exec zsh
        '';
      };
    };
}
