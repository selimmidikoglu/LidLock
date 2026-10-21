#!/bin/bash
# Renders docs/demo.gif from the app's real lock screens.
#   ./Tools/make-demo.sh
set -euo pipefail
cd "$(dirname "$0")/.."

command -v ffmpeg >/dev/null || { echo "ffmpeg is required: brew install ffmpeg" >&2; exit 1; }

frames="$(mktemp -d)"
trap 'rm -rf "$frames"' EXIT

echo "› Compiling the renderer against the app's views"
swiftc -O \
  Sources/LidLock/LockView.swift \
  Sources/LidLock/CatKnightView.swift \
  Sources/LidLock/CatFilmView.swift \
  Sources/LidLock/CatFilm.swift \
  Sources/LidLock/Preferences.swift \
  Sources/LidLock/PawDetector.swift \
  Sources/LidLock/KeyGeometry.swift \
  Tools/make-demo.swift \
  -o "$frames/make-demo"

# CatFilm resolves its frames next to the binary, the way it does inside the
# app bundle — so the demo shows the kitten whenever the clip is installed.
[ -d Resources/CatFilm ] && cp -R Resources/CatFilm "$frames/CatFilm"

echo "› Rendering frames"
"$frames/make-demo" "$frames"

echo "› Encoding docs/demo.gif"
mkdir -p docs
# One palette for the whole clip, so the dots and the armour keep their greys.
ffmpeg -y -loglevel error -framerate 8 -i "$frames/f_%04d.png" \
  -vf "fps=8,scale=600:-1:flags=lanczos,palettegen=stats_mode=diff:max_colors=128" "$frames/palette.png"
ffmpeg -y -loglevel error -framerate 8 -i "$frames/f_%04d.png" -i "$frames/palette.png" \
  -lavfi "fps=8,scale=600:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=5" \
  docs/demo.gif

ls -lh docs/demo.gif | awk '{print "› Done: docs/demo.gif ("$5")"}'
