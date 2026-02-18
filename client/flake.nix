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
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        name = "zipp-client";

        buildInputs = with pkgs; [
          flutter
          androidSdk
          jdk17
          # Linux desktop build deps
          gtk3
          pkg-config
          libepoxy
          glib
          libsysprof-capture
          pcre2
          # flutter_secure_storage_linux
          libsecret
          # Image/media
          libpng
          zlib
        ];

        shellHook = ''
          export ANDROID_SDK_ROOT="${androidSdk}/libexec/android-sdk"
          export ANDROID_HOME="$ANDROID_SDK_ROOT"
          export JAVA_HOME="${pkgs.jdk17}"
          export PATH="$ANDROID_SDK_ROOT/cmdline-tools/13.0/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"

          # Flutter config
          export FLUTTER_ROOT="${pkgs.flutter}"
          export PUB_CACHE="$HOME/.pub-cache"

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
