#!/bin/bash
# Builds build/Clipout.app. Usage: ./build.sh [--open]
#
# macOS ties the Accessibility permission to the signature. Ad hoc signing
# changes with every build, so the permission would be lost each time. With a
# self-signed certificate named "Clipout Dev" in the login keychain (see
# README) the signature stays the same and the permission survives rebuilds.
# SIGN_IDENTITY overrides the choice.
set -euo pipefail
cd "$(dirname "$0")"

# Universal binary: runs on Apple Silicon and Intel Macs.
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
APP=build/Clipout.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release "${ARCHS[@]}" --show-bin-path)/Clipout" "$APP/Contents/MacOS/Clipout"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# App icon: drawn by Resources/make-icon.swift, cached in .build.
ICON=.build/AppIcon.icns
if [[ ! -f "$ICON" || Resources/make-icon.swift -nt "$ICON" ]]; then
    SET=.build/AppIcon.iconset
    rm -rf "$SET" && mkdir -p "$SET"
    swift Resources/make-icon.swift "$SET/icon_512x512@2x.png" >/dev/null
    for px in 16 32 128 256 512; do
        sips -z $px $px "$SET/icon_512x512@2x.png" --out "$SET/icon_${px}x${px}.png" >/dev/null
        sips -z $((px * 2)) $((px * 2)) "$SET/icon_512x512@2x.png" --out "$SET/icon_${px}x${px}@2x.png" >/dev/null
    done
    iconutil -c icns "$SET" -o "$ICON"
fi
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    if security find-identity -p codesigning 2>/dev/null | grep -q '"Clipout Dev"'; then
        SIGN_IDENTITY="Clipout Dev"
    else
        SIGN_IDENTITY="-"
        echo "Hinweis: kein Zertifikat \"Clipout Dev\" – ad hoc signiert, Bedienungshilfen nach dem Start neu erlauben."
    fi
fi
codesign --force --sign "$SIGN_IDENTITY" --identifier com.ihonomic.clipout "$APP"
echo "Fertig: $APP"

if [[ "${1:-}" == "--open" ]]; then
    pkill -x Clipout 2>/dev/null || true
    open "$APP"
fi
