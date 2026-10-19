#!/bin/zsh
# Builds Notchboard and installs it to ~/Applications/Notchboard.app.
#
# The bundle is updated in place with the app stopped: deleting a bundle
# that is running makes macOS report the app as "prevented from modifying
# apps" (App Management), a permission it never needs.
set -e
cd "$(dirname "$0")"
swift build -c release

LABEL=app.notchboard
VERSION=${VERSION:-0.2.0}
APP="$HOME/Applications/Notchboard.app"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
pkill -x Notchboard 2>/dev/null || true

scripts/bundle.sh .build/release "$APP" "$VERSION"
codesign --force --sign - "$APP"

if [[ ! -f "$AGENT" ]]; then
  cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$APP/Contents/MacOS/Notchboard</string></array>
  <key>RunAtLoad</key><true/>
  <key>ProcessType</key><string>Interactive</string>
</dict></plist>
PLIST
fi
launchctl bootstrap "gui/$(id -u)" "$AGENT"
echo "$APP"
