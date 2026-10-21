#!/bin/bash
# Builds, signs, notarizes and publishes a LidLock release.
#
#   ./release.sh 1.0.0
#
# Needs two things a paid Apple Developer Program account provides:
#
#   1. a "Developer ID Application" certificate
#      Xcode › Settings › Apple Accounts › <team> › Manage Certificates › +
#   2. a stored notary credential profile
#      xcrun notarytool store-credentials LidLock \
#        --apple-id <you@example.com> --team-id <TEAMID> --password <app-specific-password>
#
# The app is built from a clean export of HEAD, never from the working tree, so
# the release contains exactly what the repository contains — no local kitten
# frames, no stale files.
set -euo pipefail
cd "$(dirname "$0")"

step() { printf '\n\033[1m› %s\033[0m\n' "$1"; }
die() { printf '\n\033[31m✗ %s\033[0m\n\n' "$1" >&2; exit 1; }

VERSION="${1:-}"
[ -n "$VERSION" ] || die "usage: ./release.sh <version>   e.g. ./release.sh 1.0.0"
PROFILE="${NOTARY_PROFILE:-LidLock}"
PLIST="Resources/Info.plist"
DIST="dist"

identity="$(security find-identity -v -p codesigning |
            awk -F'"' '/Developer ID Application/{print $2; exit}')"
[ -n "$identity" ] || die "No 'Developer ID Application' certificate in the keychain.
  Xcode › Settings › Apple Accounts › <team> › Manage Certificates › + › Developer ID Application"

xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
  || die "No notary credentials stored under the profile '$PROFILE'.
  xcrun notarytool store-credentials $PROFILE --apple-id <you> --team-id <TEAMID> --password <app-specific>"

[ -z "$(git status --porcelain)" ] || die "Working tree is dirty. Commit or stash first —
  the release is built from HEAD, so uncommitted work would silently be left out."

git rev-parse "v$VERSION" >/dev/null 2>&1 && die "Tag v$VERSION already exists."

step "Stamping version $VERSION"
# Before the build: the signature covers Info.plist.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(date +%Y%m%d%H%M)" "$PLIST"
git add "$PLIST"
git commit -q -m "Release $VERSION"
git tag "v$VERSION"

export_dir="$(mktemp -d)"
trap 'rm -rf "$export_dir"' EXIT
git archive HEAD | tar -x -C "$export_dir"
APP="$export_dir/build/LidLock.app"

step "Building and signing as: $identity"
CODESIGN_IDENTITY="$identity" "$export_dir/build.sh"

# The kitten frames are not ours to redistribute; a clean export cannot contain
# them, and this is the assertion that says so out loud.
[ -d "$APP/Contents/Resources/CatFilm" ] \
  && die "Third-party kitten frames ended up in the bundle — refusing to publish."

mkdir -p "$DIST"
upload="$DIST/LidLock-$VERSION-upload.zip"
ditto -c -k --keepParent "$APP" "$upload"

step "Notarizing — Apple usually answers within a few minutes"
xcrun notarytool submit "$upload" --keychain-profile "$PROFILE" --wait

step "Stapling the ticket"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
# Gatekeeper's own verdict — the check a downloader's Mac performs.
spctl --assess --type execute --verbose=2 "$APP"

asset="$DIST/LidLock-$VERSION.zip"
rm -f "$asset" "$upload"
ditto -c -k --keepParent "$APP" "$asset"

notes="$DIST/notes-$VERSION.md"
cat > "$notes" <<EOF
macOS 14 or newer. Signed and notarized by Apple, so it opens without a
Gatekeeper warning — no right-click-Open dance.

### Install

1. Download \`LidLock-$VERSION.zip\` from **Assets** below.
2. Double-click it in Finder. \`LidLock.app\` appears next to it.
3. Drag \`LidLock.app\` into your **Applications** folder.
4. Open it. There is no Dock icon — LidLock lives in the menu bar as a
   laptop with a paw on its screen.
5. Settings opens on first launch: pick a PIN of 4–12 digits, and allow
   **Accessibility** when macOS asks. Without it the keyboard cannot be blocked.

Then: menu bar › **Lock for Cleaning**, and wipe the screen. Type your PIN to
get everything back.

Locked out? Hold the power button for ten seconds, or wait out the auto-unlock
timer — five minutes by default.

### Or build it yourself

No download to trust; this compiles from source on your own Mac and needs the
Xcode command line tools.

\`\`\`sh
curl -fsSL https://raw.githubusercontent.com/selimmidikoglu/LidLock/main/install.sh | bash
\`\`\`
EOF

step "Publishing v$VERSION"
git push -q origin main "v$VERSION"
gh release create "v$VERSION" "$asset" \
  --title "LidLock $VERSION" \
  --notes-file "$notes"

printf '\n\033[1m› Published:\033[0m %s\n\n' "$asset"
