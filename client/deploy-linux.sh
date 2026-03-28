#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$SCRIPT_DIR"

echo "==> Cleaning build cache..."
flutter clean

echo "==> Resolving dependencies..."
flutter pub get

echo "==> Building Linux release..."
flutter build linux --release

echo "==> Done. Build at build/linux/x64/release/bundle/"
