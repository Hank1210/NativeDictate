#!/bin/zsh
set -euo pipefail

SCRIPT_DIRECTORY=${0:A:h}
PROJECT_DIRECTORY=${SCRIPT_DIRECTORY:h}
DERIVED_DATA_DIRECTORY=${NATIVEDICTATE_COMMUNITY_DERIVED_DATA:-${FLOWDICTATE_COMMUNITY_DERIVED_DATA:-${PROJECT_DIRECTORY}/build/CommunityDerivedData}}
DIST_DIRECTORY=${PROJECT_DIRECTORY}/dist
VERSION=${NATIVEDICTATE_VERSION:-${FLOWDICTATE_VERSION:-4.2.0}}
PACKAGE_CLONE_DIRECTORY=${NATIVEDICTATE_PACKAGE_CLONE_DIRECTORY:-${FLOWDICTATE_PACKAGE_CLONE_DIRECTORY:-}}
PACKAGE_RESOLUTION_ARGUMENTS=()
if [[ -n ${PACKAGE_CLONE_DIRECTORY} ]]; then
    PACKAGE_RESOLUTION_ARGUMENTS=(
        -clonedSourcePackagesDirPath "${PACKAGE_CLONE_DIRECTORY}"
        -disableAutomaticPackageResolution
    )
fi
PACKAGE_NAME=NativeDictate-${VERSION}-Community
STAGING_ROOT=$(/usr/bin/mktemp -d /private/tmp/NativeDictateCommunity.XXXXXX)
STAGING_DIRECTORY=${STAGING_ROOT}/${PACKAGE_NAME}
BUILT_APP=${DERIVED_DATA_DIRECTORY}/Build/Products/Release/NativeDictate.app
PACKAGED_APP=${STAGING_DIRECTORY}/NativeDictate.app
ZIP_PATH=${DIST_DIRECTORY}/${PACKAGE_NAME}-macOS.zip
CHECKSUM_PATH=${ZIP_PATH}.sha256
ZIP_FILENAME=${ZIP_PATH:t}
ENTITLEMENTS_PATH=${PROJECT_DIRECTORY}/config/FlowDictateCommunity.entitlements
INSTALLATION_GUIDE_DE=${PROJECT_DIRECTORY}/COMMUNITY_INSTALLATION.md
INSTALLATION_GUIDE_EN=${PROJECT_DIRECTORY}/COMMUNITY_INSTALLATION_EN.md
THIRD_PARTY_NOTICES=${PROJECT_DIRECTORY}/THIRD_PARTY_NOTICES.md
FLUIDAUDIO_LICENSE=${PROJECT_DIRECTORY}/THIRD_PARTY_LICENSES/FluidAudio-Apache-2.0.txt
PROJECT_LICENSE=${PROJECT_DIRECTORY}/LICENSE
PRIVACY_NOTICE=${PROJECT_DIRECTORY}/PRIVACY.md
CHANGELOG=${PROJECT_DIRECTORY}/CHANGELOG.md

cleanup() {
    /bin/rm -rf "${STAGING_ROOT}"
}
trap cleanup EXIT

if [[ ! -d /Applications/Xcode.app ]]; then
    echo "Xcode was not found at /Applications/Xcode.app." >&2
    exit 1
fi

if [[ ! -f ${ENTITLEMENTS_PATH} || ! -f ${INSTALLATION_GUIDE_DE} || ! -f ${INSTALLATION_GUIDE_EN} || ! -f ${THIRD_PARTY_NOTICES} || ! -f ${FLUIDAUDIO_LICENSE} || ! -f ${PROJECT_LICENSE} || ! -f ${PRIVACY_NOTICE} || ! -f ${CHANGELOG} ]]; then
    echo "Community release configuration is incomplete." >&2
    exit 1
fi

/bin/rm -rf "${DERIVED_DATA_DIRECTORY}"
/bin/rm -f "${ZIP_PATH}" "${CHECKSUM_PATH}"
/bin/mkdir -p "${DIST_DIRECTORY}" "${STAGING_DIRECTORY}"

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    xcodebuild clean build \
    -project "${PROJECT_DIRECTORY}/FlowDictate.xcodeproj" \
    -scheme FlowDictate \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "${DERIVED_DATA_DIRECTORY}" \
    "${PACKAGE_RESOLUTION_ARGUMENTS[@]}" \
    CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=NO \
    ARCHS='arm64 x86_64'

if [[ ! -d ${BUILT_APP} ]]; then
    echo "The Release build did not produce NativeDictate.app." >&2
    exit 1
fi

/usr/bin/ditto "${BUILT_APP}" "${PACKAGED_APP}"
/usr/bin/xattr -cr "${PACKAGED_APP}"
# Finder/File Provider metadata can survive the recursive cleanup on folders
# backed by macOS file providers and makes codesign reject the bundle.
/usr/bin/xattr -d com.apple.FinderInfo "${PACKAGED_APP}" 2>/dev/null || true
/usr/bin/xattr -d com.apple.fileprovider.fpfs#P "${PACKAGED_APP}" 2>/dev/null || true
/usr/bin/find "${PACKAGED_APP}" \( -name '._*' -o -name '.DS_Store' \) -delete
/usr/bin/codesign \
    --force \
    --deep \
    --sign - \
    --timestamp=none \
    --options runtime \
    --entitlements "${ENTITLEMENTS_PATH}" \
    "${PACKAGED_APP}"

/usr/bin/codesign --verify --deep --strict --verbose=2 "${PACKAGED_APP}"
/bin/cp "${INSTALLATION_GUIDE_DE}" "${STAGING_DIRECTORY}/INSTALLATION-DE.md"
/bin/cp "${INSTALLATION_GUIDE_EN}" "${STAGING_DIRECTORY}/INSTALLATION-EN.md"
/bin/cp "${THIRD_PARTY_NOTICES}" "${STAGING_DIRECTORY}/THIRD-PARTY-NOTICES.md"
/bin/cp "${FLUIDAUDIO_LICENSE}" "${STAGING_DIRECTORY}/FLUIDAUDIO-APACHE-2.0.txt"
/bin/cp "${PROJECT_LICENSE}" "${STAGING_DIRECTORY}/LICENSE.txt"
/bin/cp "${PRIVACY_NOTICE}" "${STAGING_DIRECTORY}/PRIVACY.md"
/bin/cp "${CHANGELOG}" "${STAGING_DIRECTORY}/CHANGELOG.md"

/usr/bin/ditto \
    -c -k \
    --norsrc \
    --keepParent \
    "${STAGING_DIRECTORY}" \
    "${ZIP_PATH}"

(
    cd "${DIST_DIRECTORY}"
    /usr/bin/shasum -a 256 "${ZIP_FILENAME}"
) > "${CHECKSUM_PATH}"

echo "Community release created:"
echo "  ${ZIP_PATH}"
echo "  ${CHECKSUM_PATH}"
echo "This build is ad hoc signed and intentionally not notarized."
