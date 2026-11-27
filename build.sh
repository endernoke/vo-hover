#!/bin/zsh
# Builds build/VOHover.app as a universal (arm64 + x86_64) app.
#   ./build.sh         build the app
#   ./build.sh --dmg   also write build/VOHover-<version>.dmg for a release
#
# Info.plist is the source of truth for the version (CFBundleShortVersionString,
# MAJOR.MINOR.PATCH), bundle ID and minimum macOS version. CFBundleVersion is set to
# the same value in the built app.
#
# Signing: set SIGN_IDENTITY to a codesigning identity name or hash. Otherwise the
# first "Apple Development" identity in the keychain is used, else ad hoc ("-").
set -euo pipefail
cd "${0:A:h}"

DMG=false
case "${1:-}" in
  "") ;;
  --dmg) DMG=true ;;
  *) echo "Usage: $0 [--dmg]" >&2; exit 2 ;;
esac

plist() { plutil -extract "$1" raw Info.plist; }
plutil -lint -s Info.plist
VERSION=$(plist CFBundleShortVersionString)
MIN_MACOS=$(plist LSMinimumSystemVersion)
# macOS only accepts numeric versions, so semver pre-release/build suffixes aren't allowed.
[[ $VERSION =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] \
  || { echo "CFBundleShortVersionString must be MAJOR.MINOR.PATCH, got '$VERSION'" >&2; exit 1; }

APP="build/VOHover.app"
SOURCES=(Prefs.swift Engine.swift ToggleScript.swift SettingsView.swift main.swift)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
for arch in arm64 x86_64; do
  swiftc -O -target "$arch-apple-macos$MIN_MACOS" -o "build/VOHover-$arch" $SOURCES
done
lipo -create -output "$APP/Contents/MacOS/VOHover" build/VOHover-arm64 build/VOHover-x86_64
rm build/VOHover-arm64 build/VOHover-x86_64

cp Info.plist "$APP/Contents/Info.plist"
# App icon, drawn by icon/make-icon.swift (run `swift icon/make-icon.swift icon/AppIcon.icns` after changing it).
mkdir -p "$APP/Contents/Resources"
cp icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
plutil -insert CFBundleVersion -string "$VERSION" "$APP/Contents/Info.plist"

# A stable signing identity keeps the Accessibility/Automation grants across updates;
# with ad-hoc signing ("-") each new build needs the grants again.
SIGN_ID=${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/Apple Development/{print $2; exit}')}
codesign --force --sign "${SIGN_ID:--}" "$APP"
echo "Built $APP $VERSION, signed with ${SIGN_ID:-ad hoc}."

if $DMG; then
  # Disk image with the app and an Applications shortcut to drag it onto.
  DMG_PATH="build/VOHover-$VERSION.dmg"
  STAGE="build/dmg"
  rm -rf "$STAGE" "$DMG_PATH"
  mkdir -p "$STAGE"
  ditto "$APP" "$STAGE/VOHover.app"
  ln -s /Applications "$STAGE/Applications"
  # hdiutil sometimes fails with "Resource busy" on CI runners; retry a few times.
  for attempt in 1 2 3; do
    hdiutil create -quiet -volname "VOHover" -srcfolder "$STAGE" -fs HFS+ -format UDZO "$DMG_PATH" && break
    (( attempt < 3 )) || exit 1
    sleep 2
  done
  rm -rf "$STAGE"
  echo "Wrote $DMG_PATH."
fi
