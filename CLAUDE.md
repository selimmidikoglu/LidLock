# Working on LidLock

A menu bar app that blacks out the screen and swallows keyboard, trackpad and
mouse input so the Mac can be wiped clean, released by typing a PIN. A cat guard
can arm the same lock when it sees a paw on the keys.

`README.md` is the front page for users; `docs/internals.md` is the long
explanation of how everything works. This file is for whoever is editing the
code.

## Commands

```sh
./build.sh                  # → build/LidLock.app, signed with whatever identity exists
./release.sh 1.2.3          # stamp, build, notarize, staple, publish to GitHub
./Tools/make-dmg.sh build/LidLock.app dist/x.dmg    # the drag-to-Applications image
./Tools/make-demo.sh        # → docs/demo.gif, rendered from the real lock views
swift Tools/make-logo.swift Resources/AppIcon-drawn.png -45   # artwork
swift Tools/make-icon.swift Resources/AppIcon-drawn.png Resources/LidLock.icns
swift Tools/event-types.swift                        # prints event types a tap receives
```

There are no tests. Changes are checked by building, by rendering the views
offscreen (see `Tools/make-demo.swift`), and by running the app.

## Things that will cost you an hour if you do not know them

- **Triggering a lock locks the real screen.** Input is blocked until the PIN is
  typed or the timer runs out. The way out is `pkill -x LidLock` — the event tap
  dies with the process. Never fire the shortcut to "see if it works" on a
  machine you are also using.
- **The status item can be invisible and still exist.** On a notched display
  macOS silently drops menu bar items that do not fit. `CGWindowListCopyWindowInfo`
  shows the item under its bundle id even when nothing is drawn; a user can
  ⌘-drag it somewhere visible.
- **Signing with Developer ID can hang for ever.** The first `codesign` against
  a new key raises a keychain dialog, which may open on a second display where
  nobody sees it. Answer it with *Always Allow* — plain *Allow* brings it back
  on the next build.
- **`build.sh` runs under bash 3.2 with `set -u`.** An empty array expansion
  (`"${arr[@]}"`) is an unbound-variable error there, not an empty list.
- **An app opened from Downloads is translocated.** macOS runs it from a
  read-only copy whose path changes every launch, so Accessibility never
  sticks and Finder will not warn before deleting the original. The app detects
  this and says so; the disk image exists to make it not happen.
- **The audio player interrupts by default.** Two `scheduleBuffer` calls in a
  row leave only the second one audible, which is why the meow and the hiss are
  welded into one buffer in `Sounds.swift`.

## Shape of the code

| File | Holds |
|---|---|
| `LockController` | The lock itself: tap, windows, PIN matching, timers |
| `EventTap` | `CGEventTap` wrapper; resolves key codes to lower-cased characters |
| `PinStore` | Salted SHA-256 in the keychain, plus a digest per PIN prefix |
| `PawDetector`, `KeyGeometry`, `CatGuard` | Cat detection from key positions and timings |
| `LockView`, `CatKnightView`, `CatFilmView`, `ShieldWindow` | What is on screen |
| `Sounds` | Meow and hiss, one recorded and one synthesised |
| `Hotkey`, `ShortcutRecorder` | The global shortcut and the control that records it |
| `MenuBarIcon` | The status item glyph, drawn rather than shipped |

`Resources/CatFilm/` and `Resources/Sounds/` are both optional: without them the
app falls back to a drawn knight and a synthesised meow. `build.sh` copies them
when they exist, and `release.sh` refuses to publish a build missing the kitten.

## Conventions

- No dependencies, and nothing is pulled in to avoid writing twenty lines.
- Artwork is drawn in code where that is reasonable — the app icon, the menu bar
  glyph, the knight, the hiss.
- Comments explain why a thing is the way it is, not what the line does. If a
  line looks odd, the comment should say what went wrong without it.
- The PIN is lower-cased on the way in, because the tap lower-cases what it
  reads. Letters and digits are both allowed.

## Releasing

`./release.sh <version>` needs a **Developer ID Application** certificate and a
notary profile stored as `LidLock`:

```sh
xcrun notarytool store-credentials LidLock --apple-id <you> --team-id <TEAM> --password <app-specific>
```

It refuses to start on a dirty tree, commits the version bump, tags it, and
builds from `git archive HEAD` — so anything uncommitted is silently left out of
the release by design. The notarization ticket is stapled to the disk image
rather than to the app, because the image is what people download.
