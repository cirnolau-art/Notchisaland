#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h}"
source "$PROJECT_DIR/Version.env"
if [[ "$APP_VERSION" != <->.<->.<-> || "$APP_BUILD" != <-> ]]; then
    print -u2 "Version.env 中的版本号或构建号无效"
    exit 1
fi
APP_NAME="NotchIsland"
DIST="$PROJECT_DIR/dist"
APP="$DIST/$APP_NAME.app"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="$(uname -m)"
BUILD_ARGS=(-c release --disable-sandbox --package-path "$PROJECT_DIR" --sdk "$SDK" --triple "$ARCH-apple-macosx15.0")
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
mkdir -p "$DIST"
STAGING="$(mktemp -d "$DIST/.package.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
BUNDLE="$STAGING/$APP_NAME.app"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$BUNDLE/Contents/MacOS/$APP_NAME"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>NotchIsland</string>
<key>CFBundleDisplayName</key><string>灵动岛</string>
<key>CFBundleIdentifier</key><string>com.kachunlau.notchisland</string>
<key>CFBundleExecutable</key><string>NotchIsland</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
<key>CFBundleVersion</key><string>$APP_BUILD</string>
<key>NSHumanReadableCopyright</key><string>© 2026 Lau Kachun</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSCalendarsFullAccessUsageDescription</key><string>在灵动岛显示下一场日程和会议倒计时，并在开始前提醒。仅在开启日程功能后读取，不修改日历。</string>
<key>NSAppleEventsUsageDescription</key><string>读取 Music 或 Spotify 的歌曲、封面和进度，并执行播放控制。</string>
<key>NSBluetoothAlwaysUsageDescription</key><string>检测 AirPods 连接状态，并在刘海显示耳机与耳机盒电量。</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# SwiftPM may add the developer's local toolchain directory as an rpath. It has
# no place in a distributed app; any required bundled runtime lives in Frameworks.
python3 "$PROJECT_DIR/scripts/verify-release.py" --prepare "$BUNDLE"
codesign --force --sign - --identifier com.kachunlau.notchisland "$BUNDLE"
codesign --verify --strict "$BUNDLE"
python3 "$PROJECT_DIR/scripts/verify-release.py" "$BUNDLE"
if [[ -e "$APP" ]]; then
    mv "$APP" "$DIST/NotchIsland.backup.$(date +%Y%m%d-%H%M%S).app"
fi
mv "$BUNDLE" "$APP"
rmdir "$STAGING"
print "打包完成：$APP（$APP_VERSION，构建 $APP_BUILD）"
