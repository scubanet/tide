#!/usr/bin/env bash
#
# Generate and sign appcast.xml for the current Tide release. Uses
# Sparkle's `sign_update` tool (ed25519 private key from the keychain)
# and writes build/appcast.xml ready to upload as a GitHub-Release
# asset.
#
# We regenerate the FULL appcast every release (not just append) so
# users on older versions still see the chain of intermediate notes.
# Sources of historical entries:
#   • git tags (vX.Y.Z) → version
#   • CHANGELOG.md      → release-notes per entry
#   • GitHub release    → DMG download URL (predictable path)
#
# Prereqs:
#   • Sparkle's sign_update binary on PATH (env var SPARKLE_BIN points at
#     the directory that contains it; defaults to /tmp/sparkle-tools/bin
#     where the setup step extracts it).
#   • The DMG for the version being released must exist at
#     build/Tide-<version>.dmg (release.sh just wrote it).
#
# Usage:
#   ./scripts/sign_appcast.sh 0.2.0
#
set -euo pipefail

VERSION="${1:?usage: sign_appcast.sh <version>}"
SPARKLE_BIN="${SPARKLE_BIN:-/tmp/sparkle-tools/bin}"
DMG="build/Tide-${VERSION}.dmg"
APPCAST="build/appcast.xml"
REPO_URL="https://github.com/scubanet/tide"
MIN_OS="14.0"

if [[ ! -x "${SPARKLE_BIN}/sign_update" ]]; then
  echo "sign_update not found at ${SPARKLE_BIN}/sign_update" >&2
  echo "Set SPARKLE_BIN to the bin/ directory of the Sparkle release tarball." >&2
  exit 1
fi
if [[ ! -f "${DMG}" ]]; then
  echo "DMG missing: ${DMG} — run scripts/release.sh first" >&2
  exit 1
fi

#———— current release: sign the DMG ————#
# sign_update prints attribute-form output suitable for direct injection
# into the <enclosure /> tag, e.g.:
#   sparkle:edSignature="abc==" length="12345"
#
# Locally we let sign_update find the private key in the keychain.
# In CI (or any non-keychain context) export SPARKLE_PRIVATE_KEY_FILE
# pointing at a file with the raw ed25519 private-key string.
if [[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
  CURRENT_SIG=$("${SPARKLE_BIN}/sign_update" -f "${SPARKLE_PRIVATE_KEY_FILE}" "${DMG}")
else
  CURRENT_SIG=$("${SPARKLE_BIN}/sign_update" "${DMG}")
fi
CURRENT_PUBDATE=$(LC_ALL=C date -u +"%a, %d %b %Y %H:%M:%S +0000")
CURRENT_NOTES=$(awk -v ver="${VERSION}" '
  $0 ~ "^## \\[" ver "\\]" { found=1; next }
  found && $0 ~ "^## \\[" { exit }
  found { print }
' CHANGELOG.md | sed 's/^/      /')

#———— write appcast ————#
cat > "${APPCAST}" <<EOF
<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Tide</title>
    <link>${REPO_URL}</link>
    <description>Auto-update feed for Tide.</description>
    <language>en</language>

    <item>
      <title>Version ${VERSION}</title>
      <pubDate>${CURRENT_PUBDATE}</pubDate>
      <sparkle:minimumSystemVersion>${MIN_OS}</sparkle:minimumSystemVersion>
      <description><![CDATA[
${CURRENT_NOTES}
      ]]></description>
      <enclosure
        url="${REPO_URL}/releases/download/v${VERSION}/Tide-${VERSION}.dmg"
        sparkle:version="${VERSION}"
        sparkle:shortVersionString="${VERSION}"
        type="application/octet-stream"
        ${CURRENT_SIG}
      />
    </item>
EOF

#———— historical entries (best-effort: append each older tag) ————#
# Walk git tags in reverse-chronological order, skipping the current
# version. For older versions we can't re-sign (the DMG isn't around),
# so we list them without an enclosure — Sparkle will still surface the
# notes if a user is on a much older release.
for TAG in $(git tag --sort=-v:refname); do
  OLD_VERSION="${TAG#v}"
  if [[ "${OLD_VERSION}" == "${VERSION}" ]]; then continue; fi
  OLD_DATE=$(git log -1 --format=%cD "${TAG}" 2>/dev/null || true)
  if [[ -z "${OLD_DATE}" ]]; then continue; fi
  OLD_NOTES=$(awk -v ver="${OLD_VERSION}" '
    $0 ~ "^## \\[" ver "\\]" { found=1; next }
    found && $0 ~ "^## \\[" { exit }
    found { print }
  ' CHANGELOG.md | sed 's/^/      /')
  cat >> "${APPCAST}" <<EOF

    <item>
      <title>Version ${OLD_VERSION}</title>
      <pubDate>${OLD_DATE}</pubDate>
      <sparkle:minimumSystemVersion>${MIN_OS}</sparkle:minimumSystemVersion>
      <description><![CDATA[
${OLD_NOTES}
      ]]></description>
    </item>
EOF
done

cat >> "${APPCAST}" <<EOF
  </channel>
</rss>
EOF

echo ""
echo "appcast.xml ready: ${APPCAST}"
echo ""
echo "Next:"
echo "  git tag v${VERSION}"
echo "  git push --tags"
echo "  → CI uploads ${DMG} + ${APPCAST} as Release v${VERSION} assets"
echo ""
echo "Manual fallback (no CI):"
echo "  gh release create v${VERSION} ${DMG} ${APPCAST} --notes-file CHANGELOG.md"
