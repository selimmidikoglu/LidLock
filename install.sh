#!/bin/bash
# One-command install for LidLock: fetch, build, install, launch.
#
#   curl -fsSL https://raw.githubusercontent.com/selimmidikoglu/LidLock/main/install.sh | bash
#
# Nothing is downloaded but this repository — the app is built from source on
# your own machine, with Swift from the Xcode command line tools.
set -euo pipefail

REPO="${LIDLOCK_REPO:-https://github.com/selimmidikoglu/LidLock.git}"
BRANCH="${LIDLOCK_BRANCH:-main}"

step() { printf '\n\033[1m› %s\033[0m\n' "$1"; }
die() { printf '\n\033[31m✗ %s\033[0m\n\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "LidLock is a macOS app."

version="$(sw_vers -productVersion)"
[ "${version%%.*}" -ge 14 ] || die "macOS 14 or newer is required — this is $version."

command -v git >/dev/null 2>&1 || die "git is missing. Run: xcode-select --install"
command -v swift >/dev/null 2>&1 || die "swift is missing. Run: xcode-select --install"

swift_major="$(swift -version 2>/dev/null | sed -n 's/.*Swift version \([0-9][0-9]*\).*/\1/p' | head -1)"
[ -n "$swift_major" ] && [ "$swift_major" -ge 6 ] || \
  die "Swift 6 or newer is required (Xcode 16+). Found: $(swift -version 2>/dev/null | head -1)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

step "Fetching LidLock"
git clone --depth 1 --branch "$BRANCH" "$REPO" "$work/LidLock" >/dev/null 2>&1 \
  || die "Could not clone $REPO"

step "Building — the first build takes a minute"
"$work/LidLock/build.sh"

dest="/Applications"
[ -w "$dest" ] || dest="$HOME/Applications"
mkdir -p "$dest"

step "Installing to $dest"
# Swapping the bundle under a running copy confuses macOS, so stand it down.
pkill -x LidLock 2>/dev/null || true
rm -rf "$dest/LidLock.app"
cp -R "$work/LidLock/build/LidLock.app" "$dest/LidLock.app"

step "Launching"
open "$dest/LidLock.app"

cat <<'EOF'

  LidLock is installed and running. It has no Dock icon — look for the
  laptop-with-a-paw in the menu bar.

  1. Settings opens on first launch: choose a PIN (4–12 digits).
  2. Grant Accessibility when macOS asks — without it the keyboard
     cannot be blocked. System Settings › Privacy & Security › Accessibility.
  3. Menu bar › Lock for Cleaning. Type the PIN to get everything back.

  Locked out? Hold the power button for ten seconds, or wait for the
  auto-unlock timer (five minutes by default).

EOF
