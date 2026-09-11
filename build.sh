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
  STAGE=$(mktemp -d)
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  cat > "$STAGE/README.txt" <<TXT
TokenBar ${VERSION}
Drag TokenBar.app to Applications.

This build is not notarized. If macOS says the app is damaged or from an
unidentified developer, run once in Terminal:
  xattr -cr /Applications/TokenBar.app
then open it normally (or right-click → Open).
TXT
  rm -f "$DMG"
  hdiutil create -volname "TokenBar" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
  rm -rf "$STAGE"
  echo "dmg → $DMG ($(du -h "$DMG" | cut -f1))"
  shasum -a 256 "$DMG"
fi
