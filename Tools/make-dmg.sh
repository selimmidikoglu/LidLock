#!/bin/bash
# Builds the disk image people download: the app, an alias to /Applications and
# a backdrop with an arrow between them, so the only obvious move is the right
# one — dragging it out of the image rather than opening it inside.
#
#   ./Tools/make-dmg.sh build/LidLock.app dist/LidLock-1.0.0.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:?usage: make-dmg.sh <app> <output.dmg>}"
OUT="${2:?usage: make-dmg.sh <app> <output.dmg>}"
VOLUME="LidLock"

[ -d "$APP" ] || { echo "no app at $APP" >&2; exit 1; }

work="$(mktemp -d)"
staging="$work/staging"
trap 'hdiutil detach "/Volumes/$VOLUME" >/dev/null 2>&1 || true; rm -rf "$work"' EXIT

mkdir -p "$staging/.background"
cp -R "$APP" "$staging/$(basename "$APP")"
ln -s /Applications "$staging/Applications"

echo "› Drawing the backdrop"
swift Tools/make-dmg-background.swift "$work" >/dev/null
# One file holding both resolutions, so Finder picks per display.
tiffutil -cathidpicheck "$work/background.png" "$work/background@2x.png" \
  -out "$staging/.background/background.tiff" >/dev/null

# Room for the files plus slack for the filesystem itself.
megabytes=$(( $(du -sm "$staging" | cut -f1) + 40 ))

echo "› Creating a writable image"
hdiutil create -srcfolder "$staging" -volname "$VOLUME" -fs HFS+ \
  -format UDRW -size "${megabytes}m" -ov "$work/rw.dmg" >/dev/null

device=$(hdiutil attach -readwrite -noverify -noautoopen "$work/rw.dmg" |
         grep '^/dev/' | head -1 | awk '{print $1}')
# The mount is asynchronous; Finder cannot lay out a window that is not there.
for _ in $(seq 1 30); do [ -d "/Volumes/$VOLUME" ] && break; sleep 0.2; done

echo "› Laying out the window"
osascript <<APPLESCRIPT >/dev/null
tell application "Finder"
  tell disk "$VOLUME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {300, 160, 940, 560}
    set options to the icon view options of container window
    set arrangement of options to not arranged
    set icon size of options to 128
    set text size of options to 13
    set background picture of options to file ".background:background.tiff"
    set position of item "$(basename "$APP")" of container window to {160, 230}
    set position of item "Applications" of container window to {480, 230}
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$device" >/dev/null

echo "› Compressing"
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
hdiutil convert "$work/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null

ls -lh "$OUT" | awk '{print "› Done: '"$OUT"' ("$5")"}'
