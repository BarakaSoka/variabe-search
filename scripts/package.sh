#!/bin/bash
# Builds a free, unnotarized DMG of Variabe Search for a GitHub Release: ad-hoc signed, Apple Silicon only.
#   scripts/package.sh               Output: build.noindex/package/VariabeSearch-<version>.dmg
# Without a Developer ID, macOS blocks the first launch; users allow it once in System Settings > Privacy & Security
# (or right-click > Open). scripts/release.sh makes the signed, notarized DMG instead.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
APP="build.noindex/Variabe Search.app"
OUT=build.noindex/package
rm -rf "$OUT"
mkdir -p "$OUT"

SIGN_ID=- ./build.sh
codesign --verify --strict --deep --verbose=2 "$APP"

# The DMG: the app beside a link to /Applications.
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Variabe Search.app"
ln -s /Applications "$STAGE/Applications"
DMG="$OUT/VariabeSearch-$VERSION.dmg"
hdiutil create -quiet -volname "Variabe Search" -srcfolder "$STAGE" -fs HFS+ -format ULFO -ov "$DMG"
rm -rf "$STAGE"
echo "Packaged $DMG ($(du -h "$DMG" | cut -f1))"
