#!/usr/bin/env bash
set -euo pipefail

# Scripts/build-dmg.sh
# Compiles Meridian.app in Release configuration and packages it into a compressed DMG installer.

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
DERIVED_DATA_DIR="${BUILD_DIR}/DerivedData"
STAGING_DIR="${BUILD_DIR}/DMGStaging"
DMG_OUTPUT="${1:-${BUILD_DIR}/Meridian.dmg}"
APP_NAME="Meridian.app"

SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"

echo "==> Building ${APP_NAME} in Release configuration..."
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
    -project "${PROJECT_DIR}/Meridian.xcodeproj" \
    -scheme Meridian \
    -configuration Release \
    -derivedDataPath "${DERIVED_DATA_DIR}" \
    CODE_SIGN_IDENTITY="${SIGN_IDENTITY}" \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES \
    ENABLE_HARDENED_RUNTIME=NO \
    > /dev/null

BUILT_APP="${DERIVED_DATA_DIR}/Build/Products/Release/${APP_NAME}"

if [ ! -d "${BUILT_APP}" ]; then
    echo "Error: Built app bundle not found at ${BUILT_APP}" >&2
    exit 1
fi

echo "==> Preparing DMG staging directory..."
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"

cp -R "${BUILT_APP}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

echo "==> Packaging DMG image..."
rm -f "${DMG_OUTPUT}"
mkdir -p "$(dirname "${DMG_OUTPUT}")"

hdiutil create \
    -volname "Meridian" \
    -srcfolder "${STAGING_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_OUTPUT}" \
    > /dev/null

rm -rf "${STAGING_DIR}"

if [ "${SIGN_IDENTITY}" != "-" ]; then
    echo "==> Signing DMG with identity: ${SIGN_IDENTITY}"
    codesign --force --sign "${SIGN_IDENTITY}" "${DMG_OUTPUT}"
fi

echo "==> Verifying generated DMG..."
MOUNT_DIR=$(mktemp -d /tmp/meridian_dmg_mount.XXXXXX)
hdiutil attach "${DMG_OUTPUT}" -mountpoint "${MOUNT_DIR}" -nobrowse -readonly > /dev/null

if [ -d "${MOUNT_DIR}/${APP_NAME}" ]; then
    echo "  - App bundle check: PASSED"
    codesign -v "${MOUNT_DIR}/${APP_NAME}" && echo "  - Code signature check: PASSED"
else
    echo "  - App bundle check: FAILED" >&2
    hdiutil detach "${MOUNT_DIR}" > /dev/null
    rm -rf "${MOUNT_DIR}"
    exit 1
fi

hdiutil detach "${MOUNT_DIR}" > /dev/null
rm -rf "${MOUNT_DIR}"

DMG_SIZE=$(du -h "${DMG_OUTPUT}" | cut -f1)
echo "==> DMG successfully created: ${DMG_OUTPUT} (${DMG_SIZE})"
