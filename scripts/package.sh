#!/bin/zsh
# Builds a universal Notchboard.app and a drag-to-install DMG in dist/.
# Usage: scripts/package.sh <version>
#
# With IDENTITY set ("Developer ID Application: Name (TEAMID)") the app is signed
# with the Hardened Runtime; with NOTARY_PROFILE set too (a notarytool keychain
# profile) the DMG is notarized and stapled. Without them the app is signed ad hoc,
# and macOS asks the user to approve it once (see the README).
set -e
cd "$(dirname "$0")/.."
VERSION=${1:?usage: scripts/package.sh <version>}

swift build -c release --arch arm64 --arch x86_64
BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)

rm -rf dist && mkdir -p dist/stage
APP=dist/stage/Notchboard.app
scripts/bundle.sh "$BIN" "$APP" "$VERSION"

if [[ -n "$IDENTITY" ]]; then
  codesign --force --options runtime --timestamp \
    --entitlements Support/Notchboard.entitlements --sign "$IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"

ln -s /Applications dist/stage/Applications
# A fixed name keeps releases/latest/download/Notchboard.dmg a stable link.
DMG="dist/Notchboard.dmg"
hdiutil create -quiet -volname Notchboard -srcfolder dist/stage -fs HFS+ -format UDZO "$DMG"
rm -rf dist/stage

if [[ -n "$IDENTITY" ]]; then
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
  if [[ -n "$NOTARY_PROFILE" ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
  fi
fi
shasum -a 256 "$DMG"
