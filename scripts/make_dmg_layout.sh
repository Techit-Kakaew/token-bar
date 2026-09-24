#!/bin/zsh
# One-time (needs Finder, i.e. a real Mac session): lays out a template DMG window and saves its .DS_Store
# to Assets/dmg/DS_Store so CI can reuse it without Finder.
set -euo pipefail
cd "$(dirname "$0")/.."
./build.sh >/dev/null
STAGE=$(mktemp -d); VOL="TokenBar"
cp -R dist/TokenBar.app "$STAGE/"; ln -s /Applications "$STAGE/Applications"
mkdir -p "$STAGE/.background"; cp Assets/dmg/background.png Assets/dmg/background@2x.png "$STAGE/.background/"
RW=$(mktemp -u).dmg
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov -format UDRW -fs HFS+ "$RW" >/dev/null
hdiutil detach "/Volumes/$VOL" -quiet 2>/dev/null || true
hdiutil attach "$RW" -noautoopen >/dev/null
osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 520}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 13
    set background picture of opts to file ".background:background.png"
    set position of item "TokenBar.app" of container window to {180, 200}
    set position of item "Applications" of container window to {480, 200}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT
sync; sleep 1
cp "/Volumes/$VOL/.DS_Store" Assets/dmg/DS_Store
hdiutil detach "/Volumes/$VOL" -quiet
rm -rf "$STAGE" "$RW"
echo "saved Assets/dmg/DS_Store ($(stat -f%z Assets/dmg/DS_Store) bytes)"
