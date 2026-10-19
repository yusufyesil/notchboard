#!/bin/zsh
# Assembles Notchboard.app from a SwiftPM build folder.
# Usage: scripts/bundle.sh <swift build bin path> <path to Notchboard.app> <version>
# Updates the bundle in place; it never deletes it (see build.sh).
set -e
BIN=$1 APP=$2 VERSION=$3
LABEL=app.notchboard

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/en.lproj"
cp "$BIN/Notchboard" "$APP/Contents/MacOS/Notchboard"
# Translations go where Bundle.main finds them; English is the source text itself.
cp -R "$BIN/Notchboard_Notchboard.bundle/Contents/Resources/" "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Notchboard</string>
  <key>CFBundleDisplayName</key><string>Notchboard</string>
  <key>CFBundleIdentifier</key><string>$LABEL</string>
  <key>CFBundleExecutable</key><string>Notchboard</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>tr</string></array>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>To open the chat you click in the right Claude profile.</string>
</dict></plist>
PLIST
