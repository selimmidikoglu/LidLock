#!/bin/bash
# Builds, signs, notarizes and publishes a LidLock release.
#
#   ./release.sh 1.0.0
#
# Needs two things that only exist with a paid Apple Developer Program account:
#
#   1. a "Developer ID Application" certificate
#      Xcode › Settings › Accounts › Manage Certificates › + › Developer ID Application
#   2. a stored notary credential profile
#      xcrun notarytool store-credentials LidLock \
#        --apple-id <you@example.com> --team-id <TEAMID> --password <app-specific-password>
set -euo pipefail
cd "$(dirname "$0")"

step() { printf '\n\033[1m› %s\033[0m\n' "$1"; }
die() { printf '\n\033[31m✗ %s\033[0m\n\n' "$1" >&2; exit 1; }

VERSION="${1:-}"
[ -n "$VERSION" ] || die "usage: ./release.sh <version>   e.g. ./release.sh 1.0.0"
PROFILE="${NOTARY_PROFILE:-LidLock}"
PLIST="Resources/Info.plist"
APP="build/LidLock.app"
DIST="dist"

identity="$(security find-identity -v -p codesigning |
            awk -F'"' '/Developer ID Application/{print $2; exit}')"
[ -n "$identity" ] || die "No 'Developer ID Application' certificate in the keychain.
  A free personal team cannot create one — the Apple Developer Program is required.
  Once enrolled: Xcode › Settings › Accounts › Manage Certificates › + › Developer ID Application"

xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
  || die "No notary credentials stored under the profile '$PROFILE'.
  xcrun notarytool store-credentials $PROFILE --apple-id <you> --team-id <TEAMID> --password <app-specific>"

step "Stamping version $VERSION"
# Before the build, because the signature covers Info.plist.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(date +%Y%m%d%H%M)" "$PLIST"

step "Building and signing as: $identity"
CODESIGN_IDENTITY="$identity" ./build.sh

mkdir -p "$DIST"
upload="$DIST/LidLock-$VERSION-upload.zip"
ditto -c -k --keepParent "$APP" "$upload"

step "Notarizing — Apple usually answers in a couple of minutes"
xcrun notarytool submit "$upload" --keychain-profile "$PROFILE" --wait

step "Stapling the ticket"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
# Gatekeeper's own verdict, the same check a downloader's Mac performs.
spctl --assess --type execute --verbose=2 "$APP"

asset="$DIST/LidLock-$VERSION.zip"
rm -f "$asset" "$upload"
ditto -c -k --keepParent "$APP" "$asset"

step "Publishing v$VERSION"
gh release create "v$VERSION" "$asset" \
  --title "LidLock $VERSION" \
  --notes "Signed and notarized. Download, unzip, drag to Applications.

Or build it yourself:

    curl -fsSL https://raw.githubusercontent.com/selimmidikoglu/LidLock/main/install.sh | bash"

printf '\n\033[1m› Done.\033[0m Commit the version bump in %s.\n\n' "$PLIST"
