# Zipp — Flutter Client

Flutter client for Zipp. Supports Linux desktop, Android, and web.

## Prerequisites

- [Nix](https://nixos.org/) with flakes enabled
- The dev shell in `client/flake.nix` provides Flutter, the Android SDK, and all Linux build dependencies

## Dev shell

```bash
cd client
nix develop
```

This drops you into a shell with `flutter`, `dart`, the Android SDK, and all pkg-config libraries needed for the Linux desktop build.

## Setup

```bash
flutter pub get
```

## Running

### Run on Linux

```bash
flutter run -d linux
```

### Run in browser

```bash
flutter run -d chrome
```

### Run on Android

Connect a device or start an emulator, then:

```bash
flutter run -d android
```

## Building

### Build for Linux

```bash
flutter build linux --release
# Output: build/linux/x64/release/bundle/
```

### Build for web

```bash
flutter build web --release
# Output: build/web/
```

Nginx is configured to serve directly from `client/build/web/` — no copy step needed.
After building, the updated app is live immediately.

### Build for Android

```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

## Configuration

Server URL and WebSocket URL are in [lib/config/constants.dart](lib/config/constants.dart).

- **Web**: uses same-origin relative paths automatically (no config needed when served by the Nginx setup)
- **Native desktop/Android**: uses the hardcoded production URL — update `_productionUrl` if self-hosting

For local development against a dev server, uncomment the override lines at the bottom of `constants.dart` and set your machine's IP.

## Project structure

```text
lib/
  config/         # Theme, constants
  models/         # Dart data models (User, Message, Conversation, …)
  providers/      # ChangeNotifier state (AuthProvider, ChatProvider)
  screens/        # UI screens and widgets
    widgets/      # Shared widgets (MessageBubble, ConversationTile, …)
  services/       # ApiService (HTTP), WebSocketService
```
