#!/usr/bin/env python3
"""Check the actual executable, not just its Info.plist, before shipping."""
import argparse
import json
from pathlib import Path
import plistlib
import re
import stat
import subprocess


def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT)


def verify(app, prepare=False):
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    if not executable.is_file() or not executable.stat().st_mode & stat.S_IXUSR:
        raise ValueError("应用主程序缺失或没有执行权限")
    commands = run("otool", "-l", str(executable))
    rpaths = re.findall(r"cmd LC_RPATH\s+cmdsize \d+\s+path (.+?) \(offset", commands)
    removed_rpaths = []
    for path in rpaths:
        if path.startswith(("/Applications/", "/Users/", "/Library/Developer/")):
            if not prepare:
                raise ValueError("安装包包含开发机的动态库搜索路径：" + path)
            subprocess.run(["install_name_tool", "-delete_rpath", path, str(executable)], check=True)
            removed_rpaths.append(path)
    minimum = info["LSMinimumSystemVersion"]
    versions = re.findall(r"cmd LC_BUILD_VERSION\s+cmdsize \d+\s+platform \d+\s+minos ([\d.]+)", commands)
    normalize = lambda value: tuple((list(map(int, value.split("."))) + [0, 0])[:3])
    if not versions or any(normalize(v) != normalize(minimum) for v in versions):
        raise ValueError("二进制最低系统版本与 Info.plist 不一致：" + str(versions))
    dependencies = []
    for command in commands.split("Load command ")[1:]:
        if not re.search(r"cmd LC_LOAD_(?:WEAK_)?DYLIB\b", command):
            continue
        name = re.search(r"\n\s+name (.+?) \(offset", command).group(1)
        if not name.startswith(("/System/Library/", "/usr/lib/")):
            raise ValueError("发现未打包的外部动态库：" + name)
        dependencies.append(name)
    # On macOS 15 this symbol must stay optional. An unconditional import can
    # prevent dyld from starting the application, before availability checks run.
    imports = run("nm", "-m", "-u", str(executable))
    for line in imports.splitlines():
        if "_OBJC_CLASS_$_NSGlassEffectView" in line and "weak" not in line:
            raise ValueError("液态玻璃类被强链接，macOS 15 无法加载")
    report = {"version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
              "architectures": run("lipo", "-archs", str(executable)).strip(),
              "minimumMacOS": minimum, "systemLibraries": len(dependencies),
              "developerRPathsRemoved": removed_rpaths, "status": "PASS"}
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--prepare", action="store_true")
    parser.add_argument("app", type=Path)
    arguments = parser.parse_args()
    try:
        verify(arguments.app.resolve(), arguments.prepare)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, "发布检查失败：" + str(error) + "\n")
