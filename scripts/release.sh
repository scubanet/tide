#!/usr/bin/env bash
#
# Tide release builder. Reads the version from project.yml, archives a
# Release build, exports with Developer-ID signing + hardened runtime,
# wraps the .app in a DMG, then submits to Apple for notarization and
# staples the ticket.
#
# Prerequisites (one-time, see docs/RELEASE.md):
#   • Developer ID Application cert in the login keychain
#     (verify: security find-identity -v -p codesigning)
#   • notarytool keychain profile "tide-notary"
#     (created via `xcrun notarytool store-credentials tide-notary ...`)
#   • xcodegen installed (brew install xcodegen)
#
# Output:
#   build/Tide-<version>.dmg            — the notarized + stapled DMG
#   build/Tide-export/Tide.app          — the signed .app, useful for QA
#
# Usage:
#   ./scripts/release.sh
#   ./scripts/release.sh --skip-notarize   (faster local builds for sanity-check)
#
set -euo pipefail

#———— config ————#
SCHEME="Tide"
TEAM_ID="XK8V89P2QV"
SIGNING_IDENTITY="Developer ID Application: Dominik Weckherlin (${TEAM_ID})"
NOTARY_PROFILE="tide-notary"
BUILD_DIR="build"
ARCHIVE_PATH="${BUILD_DIR}/Tide.xcarchive"
EXPORT_PATH="${BUILD_DIR}/Tide-export"

#———— flags ————#
SKIP_NOTARIZE=0
for arg in "$@"; do
  case "$arg" in
    --skip-notarize) SKIP_NOTARIZE=1 ;;
    -h|--help)
      sed -n '2,/^set -e/p' "$0" | grep '^#' | sed 's/^# \{0,1\}//'
      exit 0 ;;
  esac
done

#———— version from project.yml ————#
# Form in project.yml: "    MARKETING_VERSION: \"0.2.0\""
VERSION=$(awk -F: '/^[[:space:]]+MARKETING_VERSION/ {gsub(/[[:space:]"]/,"",$2); print $2; exit}' project.yml)
if [[ -z "${VERSION}" ]]; then
  echo "Failed to read MARKETING_VERSION from project.yml" >&2
  exit 1
fi
echo "Building Tide ${VERSION}"

#———— sanity ————#
if ! security find-identity -v -p codesigning | grep -q "${SIGNING_IDENTITY}"; then
  echo "Signing identity not found in keychain:" >&2
  echo "  ${SIGNING_IDENTITY}" >&2
  echo "Run: security find-identity -v -p codesigning" >&2
  exit 1
fi
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found. brew install xcodegen" >&2
  exit 1
fi

#———— regenerate Xcode project from yml ————#
xcodegen generate

#———— 1. archive ————#
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
xcodebuild \
  -project Tide.xcodeproj \
  -scheme "${SCHEME}" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "${ARCHIVE_PATH}" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="${SIGNING_IDENTITY}" \
  DEVELOPMENT_TEAM="${TEAM_ID}" \
  ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  archive

#———— 2. export ————#
cat > "${BUILD_DIR}/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>signingCertificate</key>
  <string>Developer ID Application</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportPath "${EXPORT_PATH}" \
  -exportOptionsPlist "${BUILD_DIR}/ExportOptions.plist"

APP="${EXPORT_PATH}/Tide.app"

#———— 3. verify signature on the .app ————#
echo "→ verifying .app signature"
codesign --verify --deep --strict --verbose=2 "${APP}"
# spctl: confirms the app is acceptable to Gatekeeper. Pre-notarization
# this only checks the signature is well-formed and trusted; it doesn't
# require a notary ticket yet.
spctl --assess --type execute --verbose "${APP}" || true

#———— 4. DMG ————#
DMG_PATH="${BUILD_DIR}/Tide-${VERSION}.dmg"
DMG_TMP="${BUILD_DIR}/dmg-tmp"
rm -rf "${DMG_TMP}"
mkdir -p "${DMG_TMP}"
cp -R "${APP}" "${DMG_TMP}/"
ln -s /Applications "${DMG_TMP}/Applications"

echo "→ creating DMG"
hdiutil create \
  -volname "Tide ${VERSION}" \
  -srcfolder "${DMG_TMP}" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "${DMG_PATH}"

echo "→ signing DMG"
codesign --sign "${SIGNING_IDENTITY}" \
  --options runtime \
  --timestamp \
  "${DMG_PATH}"

#———— 5. notarize + staple ————#
if [[ "${SKIP_NOTARIZE}" -eq 1 ]]; then
  echo "→ skipping notarization (--skip-notarize)"
  echo "Done: ${DMG_PATH} (UN-notarized)"
  exit 0
fi

echo "→ submitting to Apple notary service (may take 5-15 min)"
xcrun notarytool submit "${DMG_PATH}" \
  --keychain-profile "${NOTARY_PROFILE}" \
  --wait

echo "→ stapling notary ticket"
xcrun stapler staple "${DMG_PATH}"
xcrun stapler validate "${DMG_PATH}"

#———— done ————#
echo ""
echo "Release ready: ${DMG_PATH}"
echo "Next:"
echo "  ./scripts/sign_appcast.sh ${VERSION}"
