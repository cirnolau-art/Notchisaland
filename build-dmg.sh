#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h}"
if (( $# > 1 )) || [[ $# == 1 && "$1" != --skip-build ]]; then
    print -u2 "用法：$0 [--skip-build]"
    exit 1
fi
if (( $# == 0 )); then
    "$PROJECT_DIR/build-app.sh"
fi

DIST="$PROJECT_DIR/dist"
APP="$DIST/NotchIsland.app"
PLIST="$APP/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
ARCHS="$(/usr/bin/lipo -archs "$APP/Contents/MacOS/NotchIsland")"
ARCH_LABEL="${ARCHS// /-}"
DMG="$DIST/NotchIsland-$VERSION-$ARCH_LABEL.dmg"
TOOLS="$PROJECT_DIR/.build/dmg-tools"

codesign --verify --deep --strict "$APP"
if [[ ! -x "$TOOLS/bin/python" ]]; then
    python3 -m venv "$TOOLS"
fi
if ! "$TOOLS/bin/python" -c 'import dmgbuild, ds_store, mac_alias' 2>/dev/null; then
    "$TOOLS/bin/python" -m pip install -r "$PROJECT_DIR/scripts/dmg-requirements.txt"
fi

STAGING="$(mktemp -d "$DIST/.dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
# An @2x TIFF keeps Finder's background sharp without doubling its size in points.
swift "$PROJECT_DIR/scripts/generate-dmg-background.swift" "$STAGING/background@2x.png" "$VERSION"
sips -z 430 660 -s dpiWidth 72 -s dpiHeight 72 "$STAGING/background@2x.png" --out "$STAGING/background.png" >/dev/null
tiffutil -cathidpicheck "$STAGING/background.png" "$STAGING/background@2x.png" -out "$STAGING/background.tiff" >/dev/null

"$TOOLS/bin/dmgbuild" -s "$PROJECT_DIR/scripts/dmg-settings.py" \
    -D "app=$APP" -D "background=$STAGING/background.tiff" \
    "NotchIsland $VERSION" "$STAGING/NotchIsland.dmg"
hdiutil verify "$STAGING/NotchIsland.dmg"
if [[ -e "$DMG" ]]; then
    mv "$DMG" "$DIST/NotchIsland-$VERSION-$ARCH_LABEL.backup.$(date +%Y%m%d-%H%M%S).dmg"
fi
mv "$STAGING/NotchIsland.dmg" "$DMG"
(cd "$DIST" && shasum -a 256 "${DMG:t}" > "${DMG:t}.sha256")
print "DMG 完成：$DMG（$VERSION，构建 $BUILD）"
