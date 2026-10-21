import AppKit
import Carbon
import IOKit.pwr_mgt

/// Owns the locked state: shield windows, the event tap, the sleep assertion and
/// the sliding-window PIN matcher.
final class LockController {
    static let shared = LockController()

    let state = LockState()
    private(set) var isLocked = false

    private let tap = EventTap()
    private var windows: [ShieldWindow] = []
    private var assertionID: IOPMAssertionID = IOPMAssertionID(0)
    private var previousPresentationOptions: NSApplication.PresentationOptions = []

    private var record: PinStore.Record?
    private var reason: LockReason = .cleaning
    /// Letters typed since the lock began, trimmed to the unlock word. Plain
    /// text on purpose — "human" is a ritual, not a secret.
    private var wordBuffer = ""
    private var lastHiss = Date.distantPast
    /// Trackpad events arrive in bursts — one swipe is dozens of them — so they
    /// are counted as gestures rather than as raw events.
    private var lastPointerEvent = Date.distantPast
    private let gestureGap: TimeInterval = 0.35
    /// Hashing is far too slow for the main thread, so every comparison runs here
    /// and only the resulting match length goes back to the UI.
    private let matchQueue = DispatchQueue(label: "com.selim.lidlock.match", qos: .userInitiated)
    private var stream: [Character] = []   // matchQueue only
    private var matched = 0                // matchQueue only
    private var pending: [Character] = []  // main thread only
    private var shownMatch = 0             // main thread only
    private var draining = false           // main thread only
    private var session = 0                // main thread only

    private var ticker: Timer?
    private var deadline: Date?
    private var lastInput = Date()

    enum LockError: LocalizedError {
        case noPin
        case noAccessibility
        case secureInput
        case tapFailed

        var errorDescription: String? {
            switch self {
            case .noPin:
                return "Set an unlock PIN first."
            case .noAccessibility:
                return "LidLock needs Accessibility access to block the keyboard."
            case .secureInput:
                return "Another app is reading the keyboard securely."
            case .tapFailed:
                return "Could not take over the keyboard."
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .noPin:
                return "Open LidLock Settings and choose a PIN of 4–12 digits."
            case .noAccessibility:
                return "Allow LidLock in System Settings › Privacy & Security › Accessibility, then try again."
            case .secureInput:
                return "Close any open password field (login screens, 1Password, Terminal sudo prompts) and try again."
            case .tapFailed:
                return "Quit and reopen LidLock. If it keeps failing, re-grant Accessibility access."
            }
        }
    }

    // MARK: - Locking

    func lock(reason: LockReason = .cleaning) throws {
        guard !isLocked else { return }

        let record = PinStore.load()
        // A cleaning lock is deliberate, so it insists on a PIN. A cat lock is
        // not, and releases on the unlock word whether a PIN exists or not.
        if reason == .cleaning && record == nil { throw LockError.noPin }
        guard EventTap.isPermitted else {
            EventTap.requestPermission()
            throw LockError.noAccessibility
        }
        // With secure input active the tap never receives key events, so the PIN
        // could not be typed — refuse rather than lock the user out.
        guard !IsSecureEventInputEnabled() else { throw LockError.secureInput }

        // The guard has done its job; its tap would only shadow the blocking one.
        CatGuard.shared.stop()

        self.record = record
        self.reason = reason
        session += 1
        pending.removeAll()
        wordBuffer = ""
        resetMatcher()
        if reason == .cat, CatFilm.isAvailable {
            CatFilm.load()
        }
        state.reason = reason
        state.showsKitten = reason == .cat && !CatFilm.frames.isEmpty
        state.digitsEntered = 0
        state.wordProgress = 0
        state.startedAt = Date()
        state.blockedKeys = 0
        state.blockedGestures = 0
        state.chromeVisible = true
        lastInput = Date()
        lastHiss = .distantPast
        lastPointerEvent = .distantPast

        windows = NSScreen.screens.map { ShieldWindow(screen: $0, state: state) }
        windows.forEach { $0.orderFrontRegardless() }

        NSApp.activate()
        previousPresentationOptions = NSApp.presentationOptions
        NSApp.presentationOptions = [
            .hideDock, .hideMenuBar,
            .disableProcessSwitching, .disableForceQuit,
            .disableSessionTermination, .disableHideApplication,
        ]
        CGDisplayHideCursor(CGMainDisplayID())

        tap.onCharacter = { [weak self] character in self?.ingest(character) }
        tap.onBlockedKey = { [weak self] in self?.noteKey() }
        tap.onBlockedPointer = { [weak self] in self?.notePointer() }
        guard tap.start() else {
            teardown()
            throw LockError.tapFailed
        }

        preventSleep()
        startTicker()
        isLocked = true
    }

    func unlock() {
        guard isLocked else { return }
        teardown()
        isLocked = false
        NSApp.deactivate()
    }

    private func teardown() {
        tap.stop()
        tap.onCharacter = nil
        tap.onBlockedKey = nil
        tap.onBlockedPointer = nil
        ticker?.invalidate()
        ticker = nil
        deadline = nil
        allowSleep()
        CGDisplayShowCursor(CGMainDisplayID())
        NSApp.presentationOptions = previousPresentationOptions
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        session += 1
        pending.removeAll()
        wordBuffer = ""
        resetMatcher()
        Hiss.stop()
        CatFilm.unload()
        record = nil
        state.digitsEntered = 0
        state.wordProgress = 0
        state.secondsRemaining = nil
        // Back on watch, if the user asked for it — including after a lock that
        // never got off the ground.
        CatGuard.shared.refresh()
    }

    // MARK: - PIN matching (sliding window)

    private func resetMatcher() {
        shownMatch = 0
        matchQueue.async { [weak self] in
            self?.stream.removeAll()
            self?.matched = 0
        }
    }

    private func ingest(_ character: Character) {
        if character.isLetter {
            ingestLetter(character)
            return
        }
        guard record != nil else { return }
        pending.append(character)
        drain()
    }

    /// The unlock word only exists for cat locks — a cleaning lock is held shut
    /// by the PIN alone.
    private func ingestLetter(_ letter: Character) {
        guard reason == .cat else { return }
        let word = Preferences.humanWord
        wordBuffer.append(letter)
        if wordBuffer.count > word.count {
            wordBuffer.removeFirst(wordBuffer.count - word.count)
        }
        // Longest tail of what was typed that is also a start of the word, the
        // same idea as the PIN dots.
        var matched = 0
        for length in stride(from: wordBuffer.count, through: 1, by: -1) where matched == 0 {
            if wordBuffer.suffix(length) == word.prefix(length) { matched = length }
        }
        state.wordProgress = matched
        if matched == word.count { unlock() }
    }

    /// Digits can arrive faster than they can be hashed — a cleaning cloth
    /// produces bursts — so everything typed during a pass is folded into the
    /// next one. The match length depends only on the resulting stream, never on
    /// how the digits were grouped, so coalescing changes nothing but the pace.
    private func drain() {
        guard !draining, !pending.isEmpty, let record else { return }
        draining = true
        let batch = pending
        let session = self.session
        pending.removeAll()

        matchQueue.async { [weak self] in
            guard let self else { return }
            self.stream.append(contentsOf: batch)
            if self.stream.count > record.length {
                self.stream.removeFirst(self.stream.count - record.length)
            }
            // A matching prefix can only grow by one per digit typed, so the
            // longest candidate worth testing is capped — except on legacy
            // records, which can only answer about the full PIN.
            let ceiling = record.prefixDigests == nil
                ? record.length
                : self.matched + batch.count
            self.matched = self.matchLength(ceiling: ceiling, record: record)
            let matched = self.matched
            let typed = self.stream.count

            DispatchQueue.main.async {
                self.draining = false
                guard self.session == session else {
                    self.drain()
                    return
                }
                // Dots only ever grow. A digit that fails to extend the match
                // clears the row instead of falling back to the shorter tail
                // that still matches, so a miss is unmistakable.
                let progress = record.prefixDigests == nil ? typed : matched
                self.state.digitsEntered = progress > self.shownMatch ? progress : 0
                self.shownMatch = progress
                if matched == record.length {
                    self.unlock()
                } else {
                    self.drain()
                }
            }
        }
    }

    /// Length of the longest tail of the typed stream that is also a prefix of
    /// the PIN. Called on `matchQueue`.
    private func matchLength(ceiling: Int, record: PinStore.Record) -> Int {
        var length = min(ceiling, record.length, stream.count)
        while length > 0 {
            if PinStore.matchesPrefix(String(stream.suffix(length)), record: record) { return length }
            length -= 1
        }
        return 0
    }

    // MARK: - Chrome visibility and auto-unlock

    private func noteKey() {
        state.blockedKeys += 1
        noteInput()
    }

    /// A single swipe or scroll is dozens of events. Only the start of each
    /// burst counts, so the number on screen matches what the hand did.
    private func notePointer() {
        let now = Date()
        if now.timeIntervalSince(lastPointerEvent) > gestureGap {
            state.blockedGestures += 1
        }
        lastPointerEvent = now
        noteInput()
    }

    /// Any swallowed input keeps the lock awake and brings the panel back.
    private func noteInput() {
        lastInput = Date()
        if !state.chromeVisible { state.chromeVisible = true }
    }

    private func startTicker() {
        let minutes = Preferences.autoUnlockMinutes
        deadline = minutes > 0 ? Date().addingTimeInterval(TimeInterval(minutes) * 60) : nil
        state.secondsRemaining = minutes > 0 ? minutes * 60 : nil

        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if let deadline = self.deadline {
                let remaining = deadline.timeIntervalSinceNow
                if remaining <= 0 {
                    self.unlock()
                    return
                }
                self.state.secondsRemaining = Int(remaining.rounded(.up))
            }
            if self.state.chromeVisible,
               Date().timeIntervalSince(self.lastInput) > Preferences.chromeFadeDelay {
                self.state.chromeVisible = false
            }
            self.hissIfCatIsStillThere()
        }
    }

    /// Keeps hissing only while keys are still being pressed. A cat that has
    /// walked off gets silence; an empty room never gets a sound at all.
    private func hissIfCatIsStillThere() {
        guard reason == .cat, Preferences.catHissEnabled else { return }
        let now = Date()
        guard now.timeIntervalSince(lastInput) < 2.5, now.timeIntervalSince(lastHiss) > 3 else { return }
        lastHiss = now
        Hiss.play()
    }

    // MARK: - Sleep assertion

    private func preventSleep() {
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "LidLock is locked for cleaning" as CFString,
            &id
        )
        assertionID = result == kIOReturnSuccess ? id : IOPMAssertionID(0)
    }

    private func allowSleep() {
        if assertionID != IOPMAssertionID(0) {
            IOPMAssertionRelease(assertionID)
            assertionID = IOPMAssertionID(0)
        }
    }
}
