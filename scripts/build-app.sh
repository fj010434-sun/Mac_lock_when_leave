#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
swift build --build-system native -c release --product WatchSignal
binary_dir="$(swift build --build-system native -c release --show-bin-path)"
app_dir="$project_dir/dist/WatchSignal.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/WatchSignal" "$app_dir/Contents/MacOS/WatchSignal"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>WatchSignal</string>
<key>CFBundleIdentifier</key><string>local.sunyifeng.WatchSignal</string>
<key>CFBundleName</key><string>WatchSignal</string>
<key>CFBundleDisplayName</key><string>手表离开锁屏</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>CFBundleVersion</key><string>4</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSBluetoothAlwaysUsageDescription</key><string>读取你选择的蓝牙设备信号，在判断离开工位时让 Mac 系统休眠。</string>
</dict></plist>
PLIST
plutil -lint "$app_dir/Contents/Info.plist"
codesign --force --sign - "$app_dir"
codesign --verify --strict --verbose=2 "$app_dir"
printf '已生成：%s\n' "$app_dir"
