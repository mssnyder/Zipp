#!/usr/bin/env bash
# Builds the Flutter web client and deploys it to the server for dev testing.
#
# Usage:
#   ./deploy-web.sh              # build only (outputs to build/web/)
#   ./deploy-web.sh --deploy     # build + deploy to /var/lib/zipp/web
#
# Note: in production nginx serves the web client from the Nix store.
# --deploy is for quick dev iteration without going through GitHub Actions.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY="${1:-}"

cd "$SCRIPT_DIR"

echo "==> Cleaning build cache..."
flutter clean

echo "==> Resolving dependencies..."
flutter pub get

echo "==> Building web release..."
flutter build web --release

echo "==> Done. Build at build/web/"

if [[ "$DEPLOY" == "--deploy" ]]; then
  DEST="/var/lib/zipp/web"
  echo "==> Deploying to $DEST..."
  sudo mkdir -p "$DEST"
  sudo rsync -a --delete build/web/ "$DEST/"
  sudo chown -R zipp:zipp "$DEST"
  echo "==> Deployed. Reload nginx if needed: sudo systemctl reload nginx"
fi
