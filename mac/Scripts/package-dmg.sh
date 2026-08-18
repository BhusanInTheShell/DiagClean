#!/bin/bash
#
# Builds a distributable DiagClean.dmg: universal release binary, hardened runtime,
# Developer ID signature, notarisation, stapled ticket.
#
# Each stage is skipped with a clear message rather than silently, so an unsigned local
# build and a release build differ in what they say as well as what they produce. A DMG
# that quietly skipped notarisation looks identical to one that didn't until it reaches
# somebody else's Mac and Gatekeeper refuses it.
#
# Environment:
#   SIGN_IDENTITY     "Developer ID Application: Name (TEAMID)". Skipped if unset.
#   NOTARY_PROFILE    notarytool keychain profile name. Skipped if unset.
#
# Set up the notary profile once with:
#   xcrun notarytool store-credentials "diagclean" \
#     --apple-id you@example.com --team-id TEAMID --password APP-SPECIFIC-PASSWORD
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-0.1.0}"
BUNDLE_ID="com.diagclean.mac"
STAGE="$ROOT/.build/dmg"
APP="$STAGE/DiagClean.app"
DMG="$ROOT/.build/DiagClean-$VERSION.dmg"

echo "==> Building universal release binary"
# Both architectures in one binary: a cask installs the same DMG on Apple Silicon and
# Intel, and shipping arm64-only would fail silently on older hardware.
swift build --package-path "$ROOT" -c release --arch arm64 --arch x86_64 --product DiagCleanApp
BINARY="$(swift build --package-path "$ROOT" -c release --arch arm64 --arch x86_64 --show-bin-path)/DiagCleanApp"

echo "==> Assembling the bundle"
rm -rf "$STAGE"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/DiagClean"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>DiagClean</string>
    <key>CFBundleDisplayName</key><string>DiagClean</string>
    <key>CFBundleExecutable</key><string>DiagClean</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticTermination</key><true/>
</dict>
</plist>
PLIST
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    # The hardened runtime is a precondition for notarisation, not an optional extra.
    codesign --force --deep --options runtime --timestamp \
        --sign "$SIGN_IDENTITY" "$APP"
    codesign --verify --strict --verbose=2 "$APP"
else
    echo "    SIGN_IDENTITY unset — ad-hoc signing. This build runs on this Mac only;"
    echo "    Gatekeeper will refuse it anywhere else."
    codesign --force --deep --sign - "$APP"
fi

echo "==> Building the disk image"
rm -f "$DMG"
ln -sf /Applications "$STAGE/Applications"
hdiutil create -volname "DiagClean $VERSION" -srcfolder "$STAGE" \
    -ov -format UDZO "$DMG" >/dev/null

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --sign "$SIGN_IDENTITY" "$DMG"
fi

echo "==> Notarising"
if [[ -n "${NOTARY_PROFILE:-}" && -n "${SIGN_IDENTITY:-}" ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    # Stapling is what lets the DMG open on a Mac that is offline; without it Gatekeeper
    # has to reach Apple every time.
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
else
    echo "    NOTARY_PROFILE or SIGN_IDENTITY unset — skipping notarisation."
    echo "    This DMG is NOT distributable: Gatekeeper will block it on other Macs."
fi

echo
echo "Built $DMG"
shasum -a 256 "$DMG"
