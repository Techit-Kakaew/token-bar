#!/bin/zsh
# Build TokenBar.app into ./dist.
#   ./build.sh            release build for this Mac
#   ./build.sh --install  …and copy to /Applications, relaunch
#   ./build.sh --dmg      universal (arm64 + x86_64) build, packed as dist/TokenBar-<version>.dmg
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-}"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
APP=dist/TokenBar.app

if [[ "$MODE" == "--dmg" ]]; then
  swift build -c release --arch arm64 --arch x86_64 2>&1 | tail -1
  BIN=.build/apple/Products/Release/TokenBar
  BUNDLE=.build/apple/Products/Release/TokenBar_TokenBar.bundle
else
  swift build -c release 2>&1 | tail -1
  BIN=.build/release/TokenBar
  BUNDLE=.build/release/TokenBar_TokenBar.bundle
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
cp -R "$BUNDLE" "$APP/Contents/Resources/"
# App icon: compile the asset catalog → Assets.car (what macOS 26 reads) + AppIcon.icns (older lookups)
ICON_OUT=$(mktemp -d)
xcrun actool Assets/AppIcon.xcassets --compile "$ICON_OUT" --platform macosx \
  --minimum-deployment-target 14.0 --app-icon AppIcon \
  --output-partial-info-plist "$ICON_OUT/partial.plist" >/dev/null 2>&1
cp "$ICON_OUT/Assets.car" "$ICON_OUT/AppIcon.icns" "$APP/Contents/Resources/"
rm -rf "$ICON_OUT"
codesign --force --deep --sign - "$APP" 2>/dev/null || true
echo "built $APP ($(lipo -archs "$APP/Contents/MacOS/TokenBar"))"

if [[ "$MODE" == "--install" ]]; then
  pkill -x TokenBar 2>/dev/null || true
  rm -rf /Applications/TokenBar.app
  cp -R "$APP" /Applications/
  sleep 1
  open /Applications/TokenBar.app
  echo "installed → /Applications/TokenBar.app"
fi

if [[ "$MODE" == "--dmg" ]]; then
  DMG="dist/TokenBar-${VERSION}.dmg"
  VOL="TokenBar"
  STAGE=$(mktemp -d)
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  # window dressing: background image + Finder layout captured once by scripts/make_dmg_layout.sh
  mkdir -p "$STAGE/.background"
  cp Assets/dmg/background.png Assets/dmg/background@2x.png "$STAGE/.background/"
  cp Assets/dmg/DS_Store "$STAGE/.DS_Store"
  cat > "$STAGE/.README.txt" <<TXT
TokenBar ${VERSION}
Drag TokenBar.app to Applications.

This build is not notarized. If macOS says the app is damaged or from an
unidentified developer, run once in Terminal:

  xattr -cr /Applications/TokenBar.app && codesign --force --deep --sign - /Applications/TokenBar.app

then open it normally. If it is still blocked: System Settings →
Privacy & Security → scroll down → "Open Anyway".
TXT
  rm -f "$DMG"
  RW="$STAGE.rw.dmg"
  # build read-write first so the .DS_Store / hidden flags are honoured, then compress to the shipped image
  hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov -format UDRW -fs HFS+ "$RW" >/dev/null
  if command -v SetFile >/dev/null 2>&1; then
    MNT=$(mktemp -d)
    hdiutil attach "$RW" -nobrowse -noautoopen -mountpoint "$MNT" >/dev/null
    SetFile -a V "$MNT/.background" "$MNT/.README.txt" 2>/dev/null || true
    hdiutil detach "$MNT" -quiet
  fi
  hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
  rm -rf "$STAGE" "$RW"
  echo "dmg → $DMG ($(du -h "$DMG" | cut -f1))"
  shasum -a 256 "$DMG"
fi
