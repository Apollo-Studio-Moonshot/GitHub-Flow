#!/bin/sh
# Regenerates the AppIcon asset catalog from scripts/make-icon.swift.
set -eu
cd "$(dirname "$0")/.."

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

ICONSET="GitHubFlow/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$ICONSET"

swift scripts/make-icon.swift "$TMP_DIR/icon_1024.png"

for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" "$TMP_DIR/icon_1024.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE=$((SIZE * 2))
    sips -z "$DOUBLE" "$DOUBLE" "$TMP_DIR/icon_1024.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done

echo "Wrote $ICONSET"
