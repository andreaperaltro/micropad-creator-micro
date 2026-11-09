#!/bin/bash
# Builds the MicroPad app and installs it in /Applications.
cd "$(dirname "$0")"
HERE="$(pwd)"
# Everything printed in the Terminal is also saved here:
exec > >(tee "$HERE/log-app.txt") 2>&1
trap 'RC=$?; if [ $RC -ne 0 ]; then echo; echo "Something went wrong (see above). Press Return to close."; read -r _; else echo; echo "Done: you can close this window."; fi' EXIT
set -e

[ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
[ -x /usr/local/bin/brew ] && eval "$(/usr/local/bin/brew shellenv)"

echo "== MicroPad · app =="

if ! xcrun --find swift >/dev/null 2>&1; then
  echo "Apple Command Line Tools are required."
  echo "The installer will open: finish it, then run this script again."
  xcode-select --install || true
  exit 1
fi

# Build outside the project folder so cloud-synced folders don't sync thousands of temp files.
BUILD="$HOME/Library/Caches/MicroPad-build"
echo "Building…"
swift build -c release --package-path "$HERE/app" --scratch-path "$BUILD"

APP="/Applications/MicroPad.app"

# Back up your configuration (profiles and alerts) before updating.
CONF="$HOME/Library/Application Support/MicroPad"
if [ -d "$CONF" ]; then
  mkdir -p "$HERE/config-backup"
  cp "$CONF"/*.json "$HERE/config-backup/" 2>/dev/null || true
  echo "Configuration backed up to config-backup/"
fi
pkill -x MicroPad 2>/dev/null || true
sleep 0.5
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/release/MicroPad" "$APP/Contents/MacOS/MicroPad"
cp "$HERE/app/Info.plist" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

# Each build has a new ad-hoc signature: reset the old permission so macOS asks cleanly.
tccutil reset Accessibility io.github.micropad >/dev/null 2>&1 || true

echo
echo "Installed in $APP. Launching it."
echo "macOS will ask for Accessibility permission: turn on the switch next to MicroPad."
open "$APP"
