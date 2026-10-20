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

# Third-party footage, kept out of version control — the app falls back to the
# drawn knight when it is absent.
if [ -d Resources/CatFilm ]; then
  cp -R Resources/CatFilm "$APP/Contents/Resources/CatFilm"
  echo "› Bundled kitten frames: $(ls Resources/CatFilm | wc -l | tr -d ' ')"
else
  echo "› No kitten frames, the drawn knight will stand in"
fi

if [ -n "$IDENTITY" ]; then
  echo "› Signing as: $IDENTITY"
  codesign --force --options runtime --sign "$IDENTITY" "$APP"
else
  echo "› No Developer identity found, signing ad-hoc (Accessibility permission will reset on every rebuild)"
  codesign --force --sign - "$APP"
fi

codesign --verify --verbose=1 "$APP"
echo "› Done: $APP"
