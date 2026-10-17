#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
DERIVED_DATA="${PROJECT_ROOT}/.build/DerivedData"
SOURCE_PACKAGES="${PROJECT_ROOT}/.build/SourcePackages"
APP_BUNDLE="${DERIVED_DATA}/Build/Products/Debug/Zen-ith.app"

echo "🔨 Zen-ith.app をビルドしています..."
xcodebuild \
  -project "${PROJECT_ROOT}/Zen-ith.xcodeproj" \
  -scheme "Zen-ith" \
  -configuration Debug \
  -derivedDataPath "${DERIVED_DATA}" \
  -clonedSourcePackagesDirPath "${SOURCE_PACKAGES}" \
  OTHER_SWIFT_FLAGS="-disable-sandbox" \
  build

echo "✅ ビルド完了: ${APP_BUNDLE}"

if [[ "${1:-}" == "--run" ]]; then
  echo "🚀 Zen-ith.app を起動します..."
  open "${APP_BUNDLE}"
fi
