#!/bin/zsh
# Read-only diagnosis: no sudo, permission resets, quarantine removal or app edits.
set -u
APP="${1:-/Applications/NotchIsland.app}"
if [[ ! -d "$APP" && -d "$HOME/Applications/NotchIsland.app" ]]; then
    APP="$HOME/Applications/NotchIsland.app"
fi
REPORT="${NOTCHISLAND_REPORT_DIRECTORY:-$HOME/Desktop}/NotchIsland-启动诊断-$(date +%Y%m%d-%H%M%S).txt"
PLIST="$APP/Contents/Info.plist"
EXECUTABLE="$APP/Contents/MacOS/NotchIsland"

{
    print '== NotchIsland 启动诊断 =='
    date '+%Y-%m-%d %H:%M:%S %Z'
    sw_vers
    print "CPU 架构：$(uname -m)"
    print "应用位置：$APP"
    if [[ ! -f "$PLIST" || ! -f "$EXECUTABLE" ]]; then
        print 'FAIL：没有找到完整的应用。请从 DMG 拖入应用程序后重试。'
    else
        for KEY in CFBundleShortVersionString CFBundleVersion LSMinimumSystemVersion; do
            print "$KEY：$(/usr/libexec/PlistBuddy -c "Print :$KEY" "$PLIST" 2>&1)"
        done
        print '\n== 文件类型与权限 =='
        file "$EXECUTABLE"
        stat -f '%Sp %z bytes' "$EXECUTABLE"
        print '\n== 签名完整性 =='
        codesign --verify --deep --strict --verbose=2 "$APP"
        print "签名校验退出码：$?"
        print '\n== 系统安全评估 =='
        spctl --assess --type execute --verbose=4 "$APP"
        print "安全评估退出码：$?"
        print '\n== 下载标记（只读） =='
        xattr -p com.apple.quarantine "$APP" 2>&1
        print '\n== 启动检查 =='
        BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST" 2>/dev/null)"
        if [[ "$BUILD" == <-> && "$BUILD" -ge 7 ]]; then
            "$EXECUTABLE" --startup-check
        else
            print '旧版本使用已有自检；输出可能写入旧版日志。本报告不读取歌曲和通知内容。'
            "$EXECUTABLE" --selftest
        fi
        print "启动退出码：$?"
    fi
    print '\n== 诊断结束 =='
    print '请将本报告发给开发者；报告不更改系统或应用设置。'
} > "$REPORT" 2>&1
cat "$REPORT"
print "\n报告已保存：$REPORT"
if [[ -t 0 && "${NOTCHISLAND_DIAGNOSTIC_NO_PAUSE:-0}" != 1 ]]; then
    read -r '?按回车关闭窗口…'
fi
