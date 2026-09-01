#!/bin/zsh

set -euo pipefail

ARCH="${ARCH:?ARCH is required}"
VERSION="${VERSION:?VERSION is required}"
ARCHIVE="${ARCHIVE:-BuildArtifacts/macos-${ARCH}.xcarchive}"

APP_PATH=$(find "${ARCHIVE}/Products" -name "*.app" -maxdepth 5 | head -n 1)
if [[ -z "${APP_PATH}" ]]; then
    echo "[-] no .app found in ${ARCHIVE}" >&2
    exit 1
fi

BINARY=$(find "${APP_PATH}/Contents/MacOS" -type f -perm +111 | head -n 1)
if [[ -z "${BINARY}" ]]; then
    echo "[-] no executable found in ${APP_PATH}" >&2
    exit 1
fi

LIPO_ARCHS=$(lipo -archs "${BINARY}")
echo "binary=${BINARY}"
echo "lipo-archs=${LIPO_ARCHS}"
if [[ "${LIPO_ARCHS}" != "${ARCH}" ]]; then
    echo "[-] expected a single ${ARCH} slice, got: ${LIPO_ARCHS}" >&2
    exit 1
fi

ENTITLEMENTS=$(mktemp)
cat > "${ENTITLEMENTS}" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.network.client</key>
  <true/>
  <key>com.apple.security.files.user-selected.read-write</key>
  <true/>
  <key>com.apple.security.device.audio-input</key>
  <true/>
  <key>com.apple.security.personal-information.calendars</key>
  <true/>
  <key>com.apple.security.personal-information.photos-library</key>
  <true/>
</dict>
</plist>
PLIST

STAGE=$(mktemp -d)
APP_NAME=$(basename "${APP_PATH}")
ditto "${APP_PATH}" "${STAGE}/${APP_NAME}"
xattr -cr "${STAGE}/${APP_NAME}"
while IFS= read -r nested; do
    codesign --force --sign - --timestamp=none "${nested}"
done < <(find "${STAGE}/${APP_NAME}/Contents/Frameworks" -name '*.dylib' -o -name '*.framework' | sort)
codesign --force --sign - --timestamp=none \
    --entitlements "${ENTITLEMENTS}" \
    "${STAGE}/${APP_NAME}"
codesign --verify --verbose=2 "${STAGE}/${APP_NAME}"
codesign -d --entitlements - "${STAGE}/${APP_NAME}"
ln -s /Applications "${STAGE}/Applications"
rm -f "${ENTITLEMENTS}"

DMG="BuildArtifacts/FlowDown-${VERSION}-${ARCH}.dmg"
hdiutil create \
    -volname "FlowDown ${VERSION} ${ARCH}" \
    -srcfolder "${STAGE}" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "${DMG}"
rm -rf "${STAGE}"
ls -lh "${DMG}"
echo "[+] created ${DMG}"
