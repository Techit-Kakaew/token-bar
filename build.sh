#!/bin/zsh
# Builds TokenBar.app into ./dist and (optionally) installs to /Applications.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release 2>&1 | tail -3
APP=dist/TokenBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/TokenBar "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
mkdir -p "$APP/Contents/Resources"
cp -R .build/release/TokenBar_TokenBar.bundle "$APP/Contents/Resources/"
codesign --force --deep --sign - "$APP" 2>/dev/null || true
echo "built $APP"
if [[ "${1:-}" == "--install" ]]; then
  pkill -x TokenBar 2>/dev/null || true
  rm -rf /Applications/TokenBar.app
  cp -R "$APP" /Applications/
  sleep 1
  open /Applications/TokenBar.app
  echo "installed → /Applications/TokenBar.app"
fi
