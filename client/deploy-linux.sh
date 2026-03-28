#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$SCRIPT_DIR/bundle"
BUNDLE_DIR="build/linux/x64/release/bundle"

cd "$SCRIPT_DIR"

echo "==> Cleaning build cache..."
flutter clean

echo "==> Resolving dependencies..."
if ! flutter pub get; then
    echo "FAILED: flutter pub get" >&2
    exit 1
fi

echo "==> Building Linux release..."
if ! flutter build linux --release; then
    echo "FAILED: flutter build linux" >&2
    exit 1
fi

if [ ! -d "$BUNDLE_DIR" ]; then
    echo "FAILED: $BUNDLE_DIR does not exist after build" >&2
    exit 1
fi

if [ ! -f "$BUNDLE_DIR/zipp" ]; then
    echo "FAILED: $BUNDLE_DIR/zipp binary missing — build may be corrupt" >&2
    exit 1
fi

echo "==> Syncing bundle to $DEPLOY_DIR..."
mkdir -p "$DEPLOY_DIR"
rsync -a --delete "$BUNDLE_DIR/" "$DEPLOY_DIR/"

echo "==> Done. Linux bundle deployed to $DEPLOY_DIR"
echo "    Commit client/bundle/ and rebuild NixOS to apply."
