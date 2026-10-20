<img src="docs/icon.png" width="120" align="right" alt="LidLock">

# LidLock

Lock the screen, keyboard, trackpad and mouse while you clean your MacBook, then
type a PIN to get everything back. It can also watch for a cat walking across
the keys and lock itself.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/selimmidikoglu/LidLock/main/install.sh | bash
```

One command: it clones this repository, builds the app from source with the
Swift toolchain already on your Mac, installs it to `/Applications` and launches
it. Nothing but this repository is downloaded, and there is no binary to trust —
read [`install.sh`](install.sh) first if you'd rather see it before running it.

Needs macOS 14+ and the Xcode command line tools (`xcode-select --install`).
To do it by hand instead:

```sh
git clone https://github.com/selimmidikoglu/LidLock.git
cd LidLock && ./build.sh && open build/LidLock.app
```

## How it works

| Piece | Implementation |
|---|---|
| Blocking input | `CGEventTap` at session level, swallowing keys, trackpad, mouse, media keys and the multi-touch gestures AppKit defines but CoreGraphics does not name |
| Black screen | One borderless window per display at `CGShieldingWindowLevel()` |
| System shortcuts | `NSApp.presentationOptions` disables Cmd-Tab, force quit and session termination |
| Staying awake | `IOPMAssertionCreateWithName` (no display sleep) |
| PIN | Salted SHA-256, 120k iterations, stored in the keychain — never the PIN itself |
| Dot feedback | A digest per PIN prefix, so the dots track how far the typed tail actually matches |
| Cat guard | A `listenOnly` tap feeding key positions and timings to a paw detector — no characters, nothing stored |

The PIN uses a **sliding window**: only the last _N_ digits are compared, so the
hundreds of random keypresses your cloth produces never need clearing. Type the
PIN whenever you're done and the lock releases.

The lock screen starts with no dots at all, so it never gives away how long the
PIN is. A dot appears for each digit of the typed tail that matches — formally,
the longest suffix of everything typed that is also a prefix of the PIN. Three
correct digits show three dots, and a fourth that misses clears the row rather
than falling back to the shorter tail that still matches: the dots only grow, so
a miss is unmistakable. Unlocking is unaffected — the match itself still slides,
so the PIN opens the lock wherever it lands in the stream. Stray cloth
keypresses leave the screen empty.

## Cat guard

Off until you turn it on, because it means watching the keyboard outside a lock.
When it is on, LidLock looks for two things a hand does not do:

- a **paw** — three or more neighbouring keys pressed together and held longer
  than the roll-over of fast typing, and
- a **lie-down** — three or more keys, anywhere on the board, pinned for over a
  second and a half, which is a cat settling its weight onto the keys.

Holding one key for a long time is deliberately not evidence; people lean on
backspace all day. Any modifier wipes the slate, because somebody reaching for
a shortcut is not a cat. Evidence is scored rather than acted on immediately:
a narrow paw is suggestive, a wide one is conclusive, and the **Relaxed /
Balanced / Eager** setting decides how much is enough.

When it fires, the screen locks with the keyboard, a cat knight takes the
screen, and an optional hiss plays — repeating only while keys are still being
pressed, so a cat that has walked off gets silence. Type **human** to take back
over; no PIN needed, in the spirit of [PawSense](https://www.bitboost.com/pawsense/),
which did this on Windows in the nineties and won computer science's only
Ig Nobel for it.

### The kitten

The lock can show either a drawn knight or a real kitten in armour, picked in
Settings. The drawn one lives in `CatKnightView.swift` and costs nothing — it is
shapes and a clock.

The kitten is fourteen JPEG frames in `Resources/CatFilm/`, played forward and
then back so a clip with no natural loop still cycles without a jump. They are
loaded only while a cat lock is on screen and dropped the moment it ends.

Those frames are **third-party footage and are not in version control**. A fresh
checkout has no `Resources/CatFilm/` folder, `build.sh` says so, the Settings
picker hides itself, and the drawn knight stands in. If you want your own cat
there, point `ffmpeg` at a clip of your choosing:

```sh
mkdir -p Resources/CatFilm
ffmpeg -ss 0.3 -t 1.2 -i cat.mov \
  -vf "crop=660:1140:60:75,fps=12,scale=460:794:flags=lanczos" \
  -q:v 3 Resources/CatFilm/f_%02d.jpg
```

Any count of `f_NN.jpg` frames works; they are sorted by name and played at
12 fps. Tune the `crop` to your footage — a tall portrait that fills the frame
with the cat reads best, because the top eighteen percent is faded into the
black of the lock screen.

What the guard reads is deliberately thin: a key code and a timestamp, straight
into the detector and nowhere else. No characters are resolved, nothing is
written to disk, nothing leaves the process. Unlike PawSense it also loses no
keystrokes once it fires — the blocking tap swallows events rather than
reacting to them after the fact.

## Build

```sh
./build.sh          # → build/LidLock.app
open build/LidLock.app
```

The script signs with your Apple Development identity if one exists, so the
Accessibility permission survives rebuilds. Without an identity it falls back to
ad-hoc signing and macOS resets the permission on every build.

### App icon

The icon is drawn in code, not painted: `Tools/make-logo.swift` renders the
laptop and padlock through a small perspective projection, and
`Tools/make-icon.swift` turns any square tile into a macOS icon — squircle mask,
1024 pt grid, drop shadow, `.icns`. Re-run both when the artwork changes:

```sh
swift Tools/make-logo.swift Resources/AppIcon-drawn.png -45
swift Tools/make-icon.swift Resources/AppIcon-drawn.png Resources/LidLock.icns
```

The arguments to `make-logo.swift` are the laptop's yaw in degrees and whether
to draw the paw on the screen — `-45` turns the laptop to the left and leaves the
padlock clear of the screen, `45` turns it the other way, and `nopaw` drops the
paw. Lock size and placement live next to `let lockW` in the same file.

`make-icon.swift` also accepts a photograph rather than a drawn tile: it finds
the dark rounded square inside one and crops to it, which is how an
AI-generated icon was turned into the first version of this bundle.

## First run

1. Launch the app — the Settings window opens because no PIN is set.
2. Choose a PIN (4–12 digits).
3. Grant **System Settings › Privacy & Security › Accessibility**.
4. Menu bar icon → **Lock for Cleaning**, or **Watch for Cats** to arm the guard.

## Ways out, in order

1. Type the PIN — or, out of a cat lock, the word `human`.
2. Wait for the auto-unlock timer (default 5 minutes, configurable).
3. Hold the power button for ten seconds.

The event tap lives inside the process — if LidLock ever dies, input comes back
immediately.

## Known limits

- **A closed lid still sleeps the Mac.** No user-space app runs during sleep, so
  wake-on-keypress can't be intercepted. Lock first, clean with the lid open.
- **Secure input.** If another app is holding a password field, the tap receives
  no keys at all. LidLock refuses to lock in that state instead of trapping you.
- **The power button** (short press) is handled below the event tap and is never
  swallowed — which is exactly why it is the last resort above.
- **Gestures need their raw type numbers.** Swipe, magnify, rotate and the rest
  are AppKit event types with no `CGEventType` constants, so they have to be
  added to the mask by number (see `EventTap.gestureEventTypes`). Miss them and
  a three-finger swipe walks past the shield into Mission Control. If something
  still escapes, `swift Tools/event-types.swift` prints every type a session tap
  actually receives while you perform it.
- **Accidental unlock** is possible in theory: with an 8-digit PIN and ~2000
  stray keypresses the odds are about 1 in 50,000. Use 9+ digits if that bothers
  you.
- **The dots leak the PIN.** Someone watching the screen can find it digit by
  digit in ~10×N tries instead of 10^N, and the stored prefix digests are
  crackable the same way. Deliberate: LidLock guards a cleaning cloth, not an
  attacker — the real boundary is the macOS login screen.

## Possible next steps

- Global hotkey to lock without reaching for the menu bar
- Keyboard backlight off while locked
- Optional Touch ID unlock alongside the PIN
- Count how often the cat guard fires, so the sensitivity can tune itself
