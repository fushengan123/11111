#!/usr/bin/env bash
#
# 打 ipa。只能在 macOS + Xcode 上跑（Windows 没有 iOS SDK，别试了）。
#
# 用法：
#   ./build-ipa.sh                     # 无签名 ipa，给 Sideloadly / AltStore 重签
#   SIGN_TEAM=ABCDE12345 ./build-ipa.sh   # 用你的开发者 Team 直接签好
#   BUNDLE_ID=com.you.esp32wol ./build-ipa.sh
#   ./build-ipa.sh out                 # 指定输出目录
#
set -euo pipefail
cd "$(dirname "$0")"

SCHEME="ESP32WOL"
PROJECT="ESP32WOL.xcodeproj"
OUT="${1:-build}"
SIGN_TEAM="${SIGN_TEAM:-}"
BUNDLE_ID="${BUNDLE_ID:-}"

command -v xcodebuild >/dev/null 2>&1 || {
  echo "✗ 没找到 xcodebuild。这个脚本需要 macOS + Xcode 15（或 GitHub Actions 的 macos runner）。"
  exit 1
}

rm -rf "$OUT"
mkdir -p "$OUT"
ARCHIVE="$OUT/$SCHEME.xcarchive"

EXTRA=()
[ -n "$BUNDLE_ID" ] && EXTRA+=("PRODUCT_BUNDLE_IDENTIFIER=$BUNDLE_ID")

echo "==> 1/3 归档 ($(xcodebuild -version | head -1))"

if [ -z "$SIGN_TEAM" ]; then
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    ${EXTRA[@]+"${EXTRA[@]}"} \
    archive >"$OUT/archive.log" 2>&1 || { tail -40 "$OUT/archive.log"; exit 1; }

  APP="$ARCHIVE/Products/Applications/$SCHEME.app"
  [ -d "$APP" ] || { echo "✗ 归档里没有 $APP"; exit 1; }

  echo "==> 2/3 打包 Payload"
  rm -rf "$OUT/Payload"
  mkdir -p "$OUT/Payload"
  cp -R "$APP" "$OUT/Payload/"
  # 顺手剔掉调试残留（如果有）
  rm -rf "$OUT/Payload/$SCHEME.app/_CodeSignature" "$OUT/Payload/$SCHEME.app/SC_Info"
  (cd "$OUT" && zip -qry "$SCHEME-unsigned.ipa" Payload)

  IPA="$OUT/$SCHEME-unsigned.ipa"
  echo "==> 3/3 完成：$IPA"
  echo "    下一步：Sideloadly 拖进去，填 Apple ID 签；或 AltStore 导入。"
else
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE" \
    DEVELOPMENT_TEAM="$SIGN_TEAM" \
    CODE_SIGN_STYLE=Automatic \
    -allowProvisioningUpdates \
    ${EXTRA[@]+"${EXTRA[@]}"} \
    archive >"$OUT/archive.log" 2>&1 || { tail -40 "$OUT/archive.log"; exit 1; }

  echo "==> 2/3 导出 ipa (Development)"
  cat >"$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>development</string>
	<key>teamID</key>
	<string>$SIGN_TEAM</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>stripSwiftSymbols</key>
	<true/>
	<key>compileBitcode</key>
	<false/>
	<key>destination</key>
	<string>export</string>
</dict>
</plist>
PLIST

  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$OUT/export" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" \
    -allowProvisioningUpdates >>"$OUT/archive.log" 2>&1 || { tail -40 "$OUT/archive.log"; exit 1; }

  IPA=$(find "$OUT/export" -name '*.ipa' | head -1)
  [ -n "$IPA" ] || { echo "✗ 导出没产出 ipa"; exit 1; }
  mv "$IPA" "$OUT/$SCHEME.ipa"
  IPA="$OUT/$SCHEME.ipa"
  echo "==> 3/3 完成：$IPA"
fi

SIZE=$(du -h "$IPA" | cut -f1)
echo "    大小 $SIZE"
shasum -a 256 "$IPA" 2>/dev/null | awk '{print "    sha256 " $1}'
