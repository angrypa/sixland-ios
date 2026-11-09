#!/usr/bin/env bash
# 在 macOS 上把 Unity 导出的 Xcode 工程打成 ipa（默认**不签名**，可在 Windows 用 Sideloadly 签名安装）。
#
# 用法：
#   chmod +x Tools/build-ios-ipa.sh
#   ./Tools/build-ios-ipa.sh <"Build/iOS" 目录> [输出目录，默认 build]
#
# 想直接出**已签名**的 ipa（需要 Apple 开发者账号 + 描述文件），额外给这几个环境变量：
#   TEAM_ID / SIGN_IDENTITY / PROVISIONING_PROFILE_SPECIFIER
# 或者放一个 ExportOptions.plist 到当前目录（脚本会用它）。
set -euo pipefail

PROJ_DIR="${1:?用法: build-ios-ipa.sh <Build/iOS 目录> [输出目录]}"
OUT_DIR="${2:-build}"
XCODEPROJ="$PROJ_DIR/Unity-iPhone.xcodeproj"

if [ ! -d "$XCODEPROJ" ]; then
  echo "[ipa] 找不到 $XCODEPROJ —— 先把 Unity 导出的 Build/iOS 整个目录放到这里" >&2
  exit 2
fi

mkdir -p "$OUT_DIR"
# 统一用**绝对路径**做 archivePath：脚本会 cd 进工程目录跑 xcodebuild，相对路径会指错地方
OUT_ABS="$(cd "$OUT_DIR" && pwd)"
ARCHIVE="$OUT_ABS/Unity-iPhone.xcarchive"

echo "[ipa] Xcode 版本："; xcodebuild -version || true
echo "[ipa] 工程目录：$PROJ_DIR"

if [ -n "${TEAM_ID:-}" ] && [ -n "${SIGN_IDENTITY:-}" ] && [ -n "${PROVISIONING_PROFILE_SPECIFIER:-}" ]; then
  echo "[ipa] 走【签名】构建：TEAM_ID=$TEAM_ID"
  ( cd "$PROJ_DIR" && xcodebuild -project Unity-iPhone.xcodeproj -scheme Unity-iPhone \
      -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
      -archivePath "$ARCHIVE" archive \
      DEVELOPMENT_TEAM="$TEAM_ID" \
      CODE_SIGN_STYLE=Manual \
      CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
      PROVISIONING_PROFILE_SPECIFIER="$PROVISIONING_PROFILE_SPECIFIER" )

  EXPORT_PLIST="${EXPORT_PLIST:-ExportOptions.plist}"
  if [ ! -f "$EXPORT_PLIST" ]; then
    echo "[ipa] 没给 ExportOptions.plist，自动生成一份 ad-hoc 的"
    cat > "$EXPORT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>ad-hoc</string>
  <key>teamID</key><string>${TEAM_ID}</string>
  <key>signingStyle</key><string>manual</string>
  <key>stripSwiftSymbols</key><true/>
  <key>compileBitcode</key><false/>
</dict></plist>
PLIST
  fi
  xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT_ABS/signed" \
      -exportOptionsPlist "$EXPORT_PLIST" -allowProvisioningUpdates
  ls -lh "$OUT_ABS/signed"/*.ipa || true
  echo "[ipa] 完成（已签名）：$OUT_ABS/signed/"
  exit 0
fi

echo "[ipa] 走【未签名】构建（拿到 ipa 后可在 Windows 用 Sideloadly 用免费 Apple ID 重签安装）"
( cd "$PROJ_DIR" && xcodebuild -project Unity-iPhone.xcodeproj -scheme Unity-iPhone \
    -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE" archive \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" CODE_SIGN_ENTITLEMENTS="" )

APP="$ARCHIVE/Products/Applications/Unity-iPhone.app"
if [ ! -d "$APP" ]; then
  echo "[ipa] archive 里没有 Unity-iPhone.app（看上面的 xcodebuild 报错）" >&2
  exit 3
fi

rm -rf "$OUT_ABS/Payload"; mkdir -p "$OUT_ABS/Payload"
cp -R "$APP" "$OUT_ABS/Payload/"
( cd "$OUT_ABS" && zip -qry "sixland-unsigned.ipa" Payload )
rm -rf "$OUT_ABS/Payload"

ls -lh "$OUT_ABS/sixland-unsigned.ipa"
echo "[ipa] 完成（未签名）：$OUT_ABS/sixland-unsigned.ipa"
