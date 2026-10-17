#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
DERIVED_DATA="${PROJECT_ROOT}/.build/DerivedDataRelease"
SOURCE_PACKAGES="${PROJECT_ROOT}/.build/SourcePackages"
DIST_DIR="${PROJECT_ROOT}/dist"
APP_NAME="Zen-ith"
GITHUB_REPO="hareruya-maro/zen-ith"
APP_BUNDLE="${DERIVED_DATA}/Build/Products/Release/${APP_NAME}.app"
STAGING_DMG_DIR="${DIST_DIR}/dmg-staging"
ZIP_PATH="${DIST_DIR}/${APP_NAME}-macOS.zip"
DMG_PATH="${DIST_DIR}/${APP_NAME}-Installer.dmg"
APPCAST_DIR="${DIST_DIR}/appcast"

echo "🧹 出力ディレクトリを初期化しています: ${DIST_DIR}"
rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}" "${APPCAST_DIR}"

echo "🔨 Release 構成で ${APP_NAME}.app をビルドしています..."
xcodebuild \
  -project "${PROJECT_ROOT}/${APP_NAME}.xcodeproj" \
  -scheme "${APP_NAME}" \
  -configuration Release \
  -derivedDataPath "${DERIVED_DATA}" \
  -clonedSourcePackagesDirPath "${SOURCE_PACKAGES}" \
  OTHER_SWIFT_FLAGS="-disable-sandbox" \
  build

cp -R "${APP_BUNDLE}" "${DIST_DIR}/${APP_NAME}.app"

# Developer ID 証明書が環境変数 DEVELOPER_ID_APPLICATION で指定されている場合は署名を実行
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  echo "🔏 Developer ID でコード署名を実行しています: ${DEVELOPER_ID_APPLICATION}"
  # Sparkle.framework 内部の XPC サービス・ヘルパーを含めて署名
  codesign --force --deep --options runtime \
    --entitlements "${PROJECT_ROOT}/${APP_NAME}/${APP_NAME}.entitlements" \
    --sign "${DEVELOPER_ID_APPLICATION}" \
    "${DIST_DIR}/${APP_NAME}.app"
else
  echo "ℹ️ DEVELOPER_ID_APPLICATION 未指定のため Ad-hoc 署名でパッケージングします。"
  codesign --force --deep --sign - "${DIST_DIR}/${APP_NAME}.app"
fi

echo "📦 配布・Sparkle自動更新用 ZIP アーカイブを作成しています: ${ZIP_PATH}"
ditto -c -k --sequesterRsrc --keepParent "${DIST_DIR}/${APP_NAME}.app" "${ZIP_PATH}"
cp "${ZIP_PATH}" "${APPCAST_DIR}/"

echo "💿 配布用 DMG ディスクイメージを作成しています: ${DMG_PATH}"
mkdir -p "${STAGING_DMG_DIR}"
cp -R "${DIST_DIR}/${APP_NAME}.app" "${STAGING_DMG_DIR}/"
ln -s /Applications "${STAGING_DMG_DIR}/Applications"

hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${STAGING_DMG_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

rm -rf "${STAGING_DMG_DIR}"

# Sparkle の generate_appcast が存在する場合は appcast.xml の自動生成を試みる
GENERATE_APPCAST_BIN="${PROJECT_ROOT}/Vendor/Sparkle/bin/generate_appcast"
if [[ -x "${GENERATE_APPCAST_BIN}" ]]; then
  VERSION_TAG=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${DIST_DIR}/${APP_NAME}.app/Contents/Info.plist" 2>/dev/null || echo "0.1.0")
  DOWNLOAD_PREFIX="https://github.com/${GITHUB_REPO}/releases/download/v${VERSION_TAG}/"
  echo "✨ Sparkle generate_appcast で appcast.xml を生成しています..."
  if "${GENERATE_APPCAST_BIN}" --download-url-prefix "${DOWNLOAD_PREFIX}" "${APPCAST_DIR}" 2>/dev/null; then
    cp "${APPCAST_DIR}/appcast.xml" "${DIST_DIR}/appcast.xml"
    echo "✅ appcast.xml を生成しました: ${DIST_DIR}/appcast.xml"
  else
    echo "ℹ️ Sparkle EdDSA 秘密鍵がキーチェーンに未登録のため appcast.xml 生成をスキップしました。"
    echo "   初回のみ: ./Vendor/Sparkle/bin/generate_keys を実行してください。"
  fi
fi

echo "✅ パッケージング完了！"
echo "  - アプリ本体 : ${DIST_DIR}/${APP_NAME}.app"
echo "  - 配布用 ZIP : ${ZIP_PATH}"
echo "  - 配布用 DMG : ${DMG_PATH}"
if [[ -f "${DIST_DIR}/appcast.xml" ]]; then
  echo "  - Sparkle XML: ${DIST_DIR}/appcast.xml"
fi
