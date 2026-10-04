#!/bin/zsh
set -euo pipefail

SCRIPT_DIRECTORY=${0:A:h}
PROJECT_DIRECTORY=${SCRIPT_DIRECTORY:h}
DERIVED_DATA_DIRECTORY=${NATIVEDICTATE_DERIVED_DATA:-${FLOWDICTATE_DERIVED_DATA:-${PROJECT_DIRECTORY}/build/DerivedData}}
ARCHIVE_DIRECTORY=${PROJECT_DIRECTORY}/dist
VERSION=${NATIVEDICTATE_VERSION:-${FLOWDICTATE_VERSION:-4.2.0}}
APP_PATH=${DERIVED_DATA_DIRECTORY}/Build/Products/Release/NativeDictate.app
ZIP_PATH=${ARCHIVE_DIRECTORY}/NativeDictate-${VERSION}-macOS.zip

mkdir -p "${ARCHIVE_DIRECTORY}"

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    xcodebuild clean build \
    -project "${PROJECT_DIRECTORY}/FlowDictate.xcodeproj" \
    -scheme FlowDictate \
    -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "${DERIVED_DATA_DIRECTORY}"

/usr/bin/ditto -c -k --keepParent "${APP_PATH}" "${ZIP_PATH}"

NOTARY_PROFILE=${NATIVEDICTATE_NOTARY_PROFILE:-${FLOWDICTATE_NOTARY_PROFILE:-}}
if [[ -n "${NOTARY_PROFILE}" ]]; then
    xcrun notarytool submit "${ZIP_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait
    xcrun stapler staple "${APP_PATH}"
    /bin/rm -f "${ZIP_PATH}"
    /usr/bin/ditto -c -k --keepParent "${APP_PATH}" "${ZIP_PATH}"
fi

echo "Release artifact: ${ZIP_PATH}"
