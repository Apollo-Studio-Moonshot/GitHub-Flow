#!/bin/sh
# Builds GitHubFlow.app from the Xcode project.
set -eu
cd "$(dirname "$0")/.."

CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA=".build/DerivedData"
APP_DIR=".build/GitHubFlow.app"

xcodebuild \
    -project GitHubFlow.xcodeproj \
    -scheme GitHubFlow \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGN_IDENTITY=- \
    build

rm -rf "$APP_DIR"
ditto "$DERIVED_DATA/Build/Products/$CONFIGURATION/GitHubFlow.app" "$APP_DIR"

echo "Built $APP_DIR"
echo "Launch it with: open \"$APP_DIR\""
