#!/bin/sh
# Builds GitHubFlow.app from the SwiftPM executable.
set -eu
cd "$(dirname "$0")/.."

swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR=".build/GitHubFlow.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_DIR/GitHubFlow" "$APP_DIR/Contents/MacOS/GitHubFlow"
cp Support/Info.plist "$APP_DIR/Contents/Info.plist"
cp Support/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "Built $APP_DIR"
echo "Launch it with: open \"$APP_DIR\""
