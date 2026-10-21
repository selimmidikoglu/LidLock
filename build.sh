#!/bin/bash
# Builds LidLock.app into ./build and code-signs it.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/LidLock.app"
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/{print $2; exit}')}"

echo "› Building (release)"
swift build -c release --product LidLock

echo "› Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/LidLock "$APP/Contents/MacOS/LidLock"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/LidLock.icns "$APP/Contents/Resources/LidLock.icns"

# Both are optional: without the frames the drawn knight stands in, without the
# recording the meow is synthesised.
if [ -d Resources/Sounds ]; then
  cp -R Resources/Sounds "$APP/Contents/Resources/Sounds"
fi

if [ -d Resources/CatFilm ]; then
  cp -R Resources/CatFilm "$APP/Contents/Resources/CatFilm"
  echo "› Bundled kitten frames: $(ls Resources/CatFilm | wc -l | tr -d ' ')"
else
  echo "› No kitten frames, the drawn knight will stand in"
fi

if [ -n "$IDENTITY" ]; then
  echo "› Signing as: $IDENTITY"
  # Notarization rejects a signature without a secure timestamp, and only a
  # Developer ID build is ever notarized — dev builds stay offline-friendly.
  case "$IDENTITY" in
    "Developer ID"*) stamp="--timestamp" ;;
    *) stamp="" ;;
  esac
  # Unquoted on purpose: an empty $stamp must expand to no argument at all,
  # and "${stamp[@]}" is an unbound-variable error under bash 3.2 + set -u.
  codesign --force --options runtime $stamp --sign "$IDENTITY" "$APP"
else
  echo "› No Developer identity found, signing ad-hoc (Accessibility permission will reset on every rebuild)"
  codesign --force --sign - "$APP"
fi

codesign --verify --verbose=1 "$APP"
echo "› Done: $APP"
