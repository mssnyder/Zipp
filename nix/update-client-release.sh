#!/usr/bin/env bash
# Updates the clientRelease tag and fetchurl hashes in the Nix client derivations
# after GitHub Actions creates a new release.
#
# Usage: ./nix/update-client-release.sh [TAG]
#   If TAG is omitted, uses the latest release.
set -euo pipefail

REPO="mssnyder/Zipp"

if [ -n "${1:-}" ]; then
  TAG="$1"
else
  TAG=$(gh release list --repo "$REPO" --limit 1 --json tagName -q '.[0].tagName')
  echo "Latest release: $TAG"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_URL="https://github.com/$REPO/releases/download/$TAG"

echo "Prefetching web bundle..."
WEB_HASH=$(nix-prefetch-url --unpack "$BASE_URL/zipp-web.tar.gz" 2>/dev/null)
WEB_SRI=$(nix hash convert --hash-algo sha256 --to sri "$WEB_HASH" 2>/dev/null || nix-hash --type sha256 --to-sri "$WEB_HASH")
echo "  Web hash: $WEB_SRI"

echo "Prefetching Linux bundle..."
LINUX_HASH=$(nix-prefetch-url --unpack "$BASE_URL/zipp-linux.tar.gz" 2>/dev/null)
LINUX_SRI=$(nix hash convert --hash-algo sha256 --to sri "$LINUX_HASH" 2>/dev/null || nix-hash --type sha256 --to-sri "$LINUX_HASH")
echo "  Linux hash: $LINUX_SRI"

echo "Updating nix/web-client.nix..."
sed -i "s|clientRelease ? \"[^\"]*\"|clientRelease ? \"$TAG\"|" "$SCRIPT_DIR/web-client.nix"
sed -i "s|hash = \"sha256-[^\"]*\"|hash = \"$WEB_SRI\"|" "$SCRIPT_DIR/web-client.nix"

echo "Updating nix/client.nix..."
sed -i "s|clientRelease ? \"[^\"]*\"|clientRelease ? \"$TAG\"|" "$SCRIPT_DIR/client.nix"
sed -i "s|hash = \"sha256-[^\"]*\"|hash = \"$LINUX_SRI\"|" "$SCRIPT_DIR/client.nix"

echo "Done. Updated to release $TAG"
echo "Run 'nixos-rebuild switch' to apply."
