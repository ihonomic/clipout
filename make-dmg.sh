#!/bin/bash
# Builds build/Clipout.dmg: the app plus a link to /Applications, so
# installing is dragging one onto the other. The name has no version on
# purpose: the README links to releases/latest/download/Clipout.dmg.
#
# The app is signed with the self-signed "Clipout Dev" certificate, not an
# Apple Developer ID, so on another Mac Gatekeeper blocks the first launch
# until the user clicks "Open Anyway" in Privacy & Security.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
DMG="build/Clipout.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R build/Clipout.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Clipout $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
echo "Fertig: $DMG ($(du -h "$DMG" | cut -f1))"
