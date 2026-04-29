#!/usr/bin/env bash
# 一鍵編譯並打包成 SlapMac.app
# 使用：./build.sh  (預設 arm64)  或  ARCH=x86_64 ./build.sh
set -euo pipefail

cd "$(dirname "$0")"

ARCH="${ARCH:-arm64}"
TARGET="${ARCH}-apple-macos13.0"
APP="SlapMac.app"
BUNDLE_BIN="$APP/Contents/MacOS/SlapMac"

echo "==> 清理舊的建置產物"
rm -rf "$APP" SlapMac build

echo "==> 使用 swiftc 編譯主 app (target: $TARGET)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc \
    -target "$TARGET" \
    -O \
    -parse-as-library \
    -o "$BUNDLE_BIN" \
    Sources/SlapMac/*.swift

echo "==> 編譯 slap_helper CLI（獨立 process 讀 HID sensor，繞開 NSApp TCC 限制）"
swiftc \
    -target "$TARGET" \
    -O \
    -o "$APP/Contents/MacOS/slap_helper" \
    Sources/SlapHelper/*.swift

echo "==> 寫入 Info.plist"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "==> 生成 / 複製 App 圖示"
if [ ! -f Resources/AppIcon.icns ] && [ -d Resources/AppIcon.iconset ]; then
    iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
fi
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

echo "==> 臨時 ad-hoc 簽章（本機執行足夠，正式發佈請用 Developer ID）"
codesign --force --deep --sign - "$APP"

echo ""
echo "完成！打開方式："
echo "  open ./$APP"
echo ""
echo "首次啟動時，macOS 會詢問麥克風權限；允許後即可開始偵測拍打。"
