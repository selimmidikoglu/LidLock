# LidLock internals

The long version: how the lock holds, how the cat is spotted, how it is
built and released, and what it cannot do. The short version is in the
[README](../README.md).

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

The PIN is letters, digits or both, folded to lower case on its way out of the
event tap. It uses a **sliding window**: only the last _N_ characters are
compared, so the
hundreds of random keypresses your cloth produces never need clearing. Type the
PIN whenever you're done and the lock releases.

The lock screen starts with no dots at all, so it never gives away how long the
PIN is. A dot appears for each character of the typed tail that matches — formally,
the longest suffix of everything typed that is also a prefix of the PIN. Three
correct characters show three dots, and a fourth that misses clears the row rather
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

The lock shows the kitten in armour above: fourteen JPEG frames in
`Resources/CatFilm/`, played forward and then back so a clip with no natural
loop still cycles without a jump. They are loaded only while a cat lock is on
screen and dropped the moment it ends — a menu bar utility has no business
holding decoded photographs while it sits idle.

There is no setting to pick a portrait. Delete the folder and a drawn knight
stands in instead, shapes and a clock in `CatKnightView.swift`, costing nothing
and staying crisp at any size. If you want your own cat there, point `ffmpeg` at
a clip of your choosing:

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

### Releasing a signed build

```sh
./release.sh 1.0.0
```

Stamps the version, builds with the **Developer ID Application** certificate,
notarizes with `notarytool`, staples the ticket, asks Gatekeeper for the same
verdict a downloader's Mac will reach, and publishes the image as a GitHub
release.

The image is built by `Tools/make-dmg.sh`: the app, an alias to `/Applications`
and a drawn backdrop with an arrow between them, so the obvious move is the
right one. The ticket is stapled to the image rather than to the app, because
the image is what gets downloaded — and the app ejects the image itself once it
is running from Applications. It refuses to start unless both the certificate and a stored notary
profile exist, so a half-signed build never escapes.

Both need a paid Apple Developer Program account — a free personal team can only
issue "Apple Development" certificates, which Gatekeeper rejects on any machine
but the one that built them. That is why `install.sh` builds from source
instead: locally built apps need no notarization.

### The README demo

```sh
./Tools/make-demo.sh          # → docs/demo.gif
```

Renders the GIF at the top of this file from the app's own lock views, compiled
straight out of `Sources/LidLock` — the screens in the demo are the screens it
ships, not a mock-up. Needs `ffmpeg`.

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

## The two noises

The **meow** is a recording, trimmed out of a longer clip and kept in
`Resources/Sounds/meow.m4a` — fourteen kilobytes, faded at both ends so it
neither clicks nor cuts off, and normalised. Delete it and the app synthesises
one instead: a sawtooth cord whose pitch arches from 520 Hz to 700 and falls
to 360, passed through two resonators standing in for a mouth that opens from
*ee* to *aa* and closes again. The stand-in is recognisably a cat and
recognisably not a real one.

Only a cat lock makes a sound, and it makes both: meow then hiss, welded into
one buffer with a breath between them. Scheduling the two separately left them
at the mercy of what the player does with a queue while the engine is still
starting — and what it did was swallow the meow. It repeats every six
seconds for as long as keys are still being pressed, so a cat that has walked
away gets silence. A cleaning lock is silent throughout — you asked for it, you
are standing over it, and a wiping cloth does not need telling off.

The **hiss** is synthesised outright — white noise with the previous sample subtracted, which tilts it
towards the high end a cat reacts to, then shaped so it fades instead of
clicking off. Every synthesised voice is normalised to a measured peak, because
a resonator multiplies its input by whatever it likes and guessing the gain does
not work — the meow came out at five times full scale the first time.

## The lock shortcut

**⌃⌥⌘L** locks from anywhere, and Settings will record a different combination
over it — backspace while recording clears it, escape leaves it alone.

The key is claimed through Carbon's `RegisterEventHotKey` rather than a global
`NSEvent` monitor, which would need Accessibility before the user has any
reason to grant it. Carbon reports a clash only against a key this app already
holds, so a combination another app owns still registers: both end up hearing
it, and there is no supported way to ask who else is listening.

## Ways out, in order

1. Type the PIN — or, out of a cat lock, the word `human`.
2. Wait for the auto-unlock timer — 1 minute by default, anything from
   30 seconds to 30 minutes in Settings, or never.
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
- **Accidental unlock** is possible in theory, and the alphabet decides how
  remote it is: ~2000 stray keypresses against an 8-digit PIN land at roughly 1
  in 50,000, while the same cloth against 8 letters-and-digits is about 1 in a
  billion. Mix letters in, or use more characters.
- **The dots leak the PIN.** Someone watching the screen can find it one
  character at a time — ~36×N tries instead of 36^N — and the stored prefix
  digests are
  crackable the same way. Deliberate: LidLock guards a cleaning cloth, not an
  attacker — the real boundary is the macOS login screen.

## Possible next steps

- Keyboard backlight off while locked
- Optional Touch ID unlock alongside the PIN
- Count how often the cat guard fires, so the sensitivity can tune itself
