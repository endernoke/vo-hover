#!/bin/zsh
# Builds VOHover.app, installs it to ~/Applications, installs the toggle AppleScript
# for binding in VoiceOver Commands, and (re)launches the app.
# To start VOHover at login, turn on Settings > General > Open at login.
#   ./install.sh           install and open Settings
#   ./install.sh --quiet   install and start in the background
set -euo pipefail
cd "${0:A:h}"

APP="$HOME/Applications/VOHover.app"
LABEL="local.vohover"
SCRIPTS="$HOME/Library/Scripts/VOHover"

mkdir -p build "$APP/Contents/MacOS" "$SCRIPTS"
swiftc -O -o build/VOHover Prefs.swift Engine.swift SettingsView.swift main.swift

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$LABEL</string>
  <key>CFBundleName</key><string>VOHover</string>
  <key>CFBundleDisplayName</key><string>VOHover</string>
  <key>CFBundleExecutable</key><string>VOHover</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.1</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>VOHover speaks the item under the pointer through VoiceOver.</string>
</dict></plist>
EOF

# Stop any running copy before replacing the binary.
pkill -x VOHover 2>/dev/null || true
while pgrep -qx VOHover; do sleep 0.1; done

cp build/VOHover "$APP/Contents/MacOS/VOHover"
# A stable signing identity keeps the Accessibility/Automation grants across rebuilds;
# ad-hoc signing ("-") works too, but each rebuild then needs the grants again.
SIGN_ID=$(security find-identity -v -p codesigning | awk '/Apple Development/{print $2; exit}')
codesign --force --sign "${SIGN_ID:--}" "$APP"

osacompile -o "$SCRIPTS/Toggle VOHover.scpt" -e 'do shell script "pkill -USR1 -x VOHover || true"'

if [[ "${1:-}" == "--quiet" ]]; then
  open -g "$APP" --args --background
else
  open "$APP"
fi
echo "Installed $APP."
