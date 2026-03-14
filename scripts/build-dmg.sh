#!/bin/bash
# build-dmg.sh
# Creates a styled DMG installer for SinglePane.
# Requires: create-dmg (brew install create-dmg)
#
# Usage:
#   ./scripts/build-dmg.sh                          # Uses default build path
#   ./scripts/build-dmg.sh /path/to/SinglePane.app  # Uses specified app bundle

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# App bundle path — default to Xcode's DerivedData Release build
APP_PATH="${1:-${HOME}/Library/Developer/Xcode/DerivedData/singlepane-*/Build/Products/Release/SinglePane.app}"

# Resolve glob
APP_PATH=$(echo $APP_PATH)

if [ ! -d "$APP_PATH" ]; then
    echo "Error: App bundle not found at: $APP_PATH"
    echo "Usage: $0 /path/to/SinglePane.app"
    exit 1
fi

APP_NAME="SinglePane"
DMG_OUTPUT="${PROJECT_DIR}/build/${APP_NAME}.dmg"
BACKGROUND="${PROJECT_DIR}/assets/dmg/dmg-background.png"

# Clean previous build
rm -f "$DMG_OUTPUT"
mkdir -p "$(dirname "$DMG_OUTPUT")"

echo "Building DMG from: $APP_PATH"
echo "Output: $DMG_OUTPUT"

/opt/homebrew/bin/create-dmg \
    --volname "$APP_NAME" \
    --background "$BACKGROUND" \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 128 \
    --icon "$APP_NAME.app" 165 190 \
    --app-drop-link 495 190 \
    --hide-extension "$APP_NAME.app" \
    --text-size 14 \
    --no-internet-enable \
    "$DMG_OUTPUT" \
    "$APP_PATH"

echo ""
echo "DMG created: $DMG_OUTPUT"
echo "Size: $(du -h "$DMG_OUTPUT" | cut -f1)"
