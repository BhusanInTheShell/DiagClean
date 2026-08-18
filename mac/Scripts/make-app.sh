#!/bin/bash
#
# Assembles DiagClean.app from the SwiftPM build.
#
# A SwiftUI executable has to live inside a bundle with an Info.plist before macOS
# will treat it as an app — without one it launches as a background process with no
# menu bar and no Dock presence. Building the bundle here rather than committing an
# .xcodeproj keeps the whole build reproducible from the command line, which is what
# the eventual notarised-DMG and Homebrew-cask steps will hang off.
set -euo pipefail

CONFIGURATION="${1:-debug}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/.build/$CONFIGURATION"
APP="$ROOT/.build/DiagClean.app"

VERSION="0.1.0"
BUNDLE_ID="com.diagclean.mac"

echo "Building ($CONFIGURATION)…"
swift build --package-path "$ROOT" --configuration "$CONFIGURATION" --product DiagCleanApp

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BUILD_DIR/DiagCleanApp" "$APP/Contents/MacOS/DiagClean"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>DiagClean</string>
    <key>CFBundleDisplayName</key>
    <string>DiagClean</string>
    <key>CFBundleExecutable</key>
    <string>DiagClean</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signature so the app runs locally. Release builds will re-sign with a
# Developer ID identity and staple a notarisation ticket; this is only enough to
# satisfy Gatekeeper on the machine that built it.
codesign --force --sign - --timestamp=none "$APP" 2>/dev/null || \
    echo "warning: ad-hoc signing failed; the app may still run locally"

echo "Built $APP"
