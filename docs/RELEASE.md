# Release Pipeline — Tide

This is the runbook for cutting a Tide release. The whole flow boils
down to:

```
git tag v0.2.1
git push origin v0.2.1
# → GitHub Actions builds, signs, notarizes, publishes the DMG +
#   updated appcast.xml. Existing Tide installs see the update via
#   Sparkle on the next launch.
```

Everything below is the one-time setup needed before that works.

> **⚠️ Appcast-URL-Invariante.** `SUFeedURL` points at
> `releases/latest/download/appcast.xml`, and GitHub's `latest` only
> resolves to **non-prerelease** releases. If any release is ever marked
> "prerelease", every installed client silently stops seeing updates until
> a newer stable release ships. Keep releases non-prerelease, or move the
> appcast to a stable URL (e.g. a `gh-pages` branch) that doesn't depend on
> `latest`.

---

## 1. Local prerequisites

You need these once on the laptop you'll ever run a release from
(usually only for emergency manual builds — CI handles the regular
case).

| Tool              | Install                          | Verify                              |
|-------------------|----------------------------------|-------------------------------------|
| Xcode 15+         | App Store                        | `xcode-select -p`                   |
| XcodeGen          | `brew install xcodegen`          | `xcodegen --version`                |
| Developer ID cert | already in your login keychain   | `security find-identity -v -p codesigning \| grep "Developer ID Application"` |
| notarytool profile| `xcrun notarytool store-credentials tide-notary --key ... --key-id ... --issuer ...` | `xcrun notarytool history --keychain-profile tide-notary` |
| Sparkle tools     | extracted to `/tmp/sparkle-tools/` | `/tmp/sparkle-tools/bin/sign_update --help` |

Then bump `MARKETING_VERSION` in `project.yml`, add a `## [X.Y.Z]`
section to `CHANGELOG.md`, commit, and tag.

---

## 2. CI secrets (one-time, GitHub repo Settings → Secrets → Actions)

The `release.yml` workflow needs these six. Skip any and the workflow
fails on the relevant step.

### 2.1 `MACOS_CERT_P12_BASE64` + `MACOS_CERT_PASSWORD`

Export the Developer ID Application cert as a `.p12`:

```bash
# In Schlüsselbundverwaltung:
#   • Find "Developer ID Application: Dominik Weckherlin (XK8V89P2QV)"
#   • Right-click → "Exportieren …" → save as DeveloperID.p12
#   • Set a strong password — store both halves immediately
base64 -i DeveloperID.p12 -o cert.b64
```

Paste the contents of `cert.b64` into `MACOS_CERT_P12_BASE64`. Paste
the password you chose into `MACOS_CERT_PASSWORD`.

### 2.2 `KEYCHAIN_PASSWORD`

Any throwaway string. CI creates a temporary keychain on the runner
and locks it with this. It's not reused outside that one CI run.

### 2.3 `ASC_API_KEY_ID` + `ASC_API_ISSUER_ID` + `ASC_API_KEY_BASE64`

The App Store Connect API Key used for notarization.

* Key ID: 10-character ID shown in App Store Connect → Users and
  Access → Integrations → App Store Connect API.
* Issuer ID: UUID shown above the key list.
* Key (`AuthKey_XXX.p8`):

  ```bash
  base64 -i ~/.appstoreconnect/private_keys/AuthKey_*.p8 -o p8.b64
  ```

  Paste contents of `p8.b64` into `ASC_API_KEY_BASE64`.

### 2.4 `SPARKLE_ED_PRIVATE_KEY`

The ed25519 private key that pairs with `SUPublicEDKey` in
`Info.plist`. Sparkle's `generate_keys` stored it in your Keychain
under account `ed25519` of service `https://sparkle-project.org`.
Pull it out as a single line:

```bash
security find-generic-password -a ed25519 -s 'https://sparkle-project.org' -w
```

Copy the printed string into `SPARKLE_ED_PRIVATE_KEY`. (No newlines,
no decoding — keep it as the opaque base64 blob Sparkle gave you.)

> ⚠️ This key signs every Tide update users receive. Treat it like a
> code-signing private key — if it leaks, generate a new pair and
> ship a Tide release with the new `SUPublicEDKey`. Users on the old
> public key won't auto-update past the leak; they'll need a manual
> reinstall.

---

## 3. Cutting a release

1. Bump version in `project.yml` (`MARKETING_VERSION`).
2. Add a `## [X.Y.Z] — short title (YYYY-MM-DD)` section to
   `CHANGELOG.md` with what changed. The release pipeline pulls this
   section verbatim into the GitHub Release body and the
   appcast.xml description.
3. Commit + push:
   ```bash
   git commit -am "chore(release): X.Y.Z"
   git push
   ```
4. Tag and push the tag:
   ```bash
   git tag v0.2.1
   git push origin v0.2.1
   ```
5. Watch the workflow on the Actions tab. The notarization step waits
   for Apple, so a green run takes 8–20 min.

When green: existing Tide installs will see the update via Sparkle on
their next launch (Sparkle polls `SUFeedURL` daily by default).

---

## 4. Manual local release (emergency)

If CI is broken and you need to ship:

```bash
./scripts/release.sh
./scripts/sign_appcast.sh "$(awk -F: '/^[[:space:]]+MARKETING_VERSION/ {gsub(/[[:space:]"]/,"",$2); print $2; exit}' project.yml)"

VERSION=$(awk -F: '/^[[:space:]]+MARKETING_VERSION/ {gsub(/[[:space:]"]/,"",$2); print $2; exit}' project.yml)
gh release create "v${VERSION}" \
  "build/Tide-${VERSION}.dmg" \
  "build/appcast.xml" \
  --title "Tide ${VERSION}" \
  --notes-file CHANGELOG.md
```

`release.sh --skip-notarize` skips Apple's notary service for very
quick local sanity checks. The resulting DMG isn't shippable
(Gatekeeper will quarantine it), but it confirms the signing chain
is intact.
