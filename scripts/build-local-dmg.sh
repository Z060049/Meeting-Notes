#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/build"
APP_DIR="$OUTPUT_DIR/MeetingNotes.app"
STAGING_DIR="$ROOT_DIR/.build/MeetingNotes-dmg"
DMG_PATH="$OUTPUT_DIR/MeetingNotes-0.1.0-arm64.dmg"

"$ROOT_DIR/scripts/build-dev-app.sh"
mkdir -p "$OUTPUT_DIR"

# Never distribute credentials inside the application bundle. MeetingNotes also
# reads ~/.meetingnotes/.env and ~/Documents/MeetingNotes/.env at runtime.
rm -f "$APP_DIR/Contents/Resources/.env"
codesign --force --deep --sign - \
  --entitlements "$ROOT_DIR/scripts/dev.entitlements" \
  "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_DIR" "$STAGING_DIR/MeetingNotes.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "MeetingNotes" \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  -ov \
  "$DMG_PATH"

rm -rf "$STAGING_DIR"

echo "Created $DMG_PATH"
echo "This local build is ad-hoc signed and is not notarized."
