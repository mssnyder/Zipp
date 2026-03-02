#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="/var/lib/zipp/web"

cd "$SCRIPT_DIR"

echo "==> Resolving dependencies..."
if ! flutter pub get; then
    echo "FAILED: flutter pub get" >&2
    exit 1
fi

echo "==> Building web release..."
if ! flutter build web --release; then
    echo "FAILED: flutter build web" >&2
    exit 1
fi

if [ ! -d "build/web" ]; then
    echo "FAILED: build/web directory does not exist after build" >&2
    exit 1
fi

if [ ! -f "build/web/index.html" ]; then
    echo "FAILED: build/web/index.html missing — build may be corrupt" >&2
    exit 1
fi

echo "==> Deploying to $DEPLOY_DIR..."
if ! rsync -a --delete build/web/ "$DEPLOY_DIR/"; then
    echo "FAILED: rsync deploy" >&2
    exit 1
fi

echo "==> Done. Web client deployed to $DEPLOY_DIR"
