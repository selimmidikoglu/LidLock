import ApplicationServices
import CoreGraphics
import Foundation

/// Watches the keyboard while the Mac is unlocked and raises a hand when the
/// typing stops looking human.
///
/// The tap is `listenOnly`: events pass through untouched, nothing is blocked
/// and nothing is altered. What it reads is deliberately thin — a key code and
/// a timestamp — and that goes straight into `PawDetector` and nowhere else.
/// No characters are resolved, nothing is written to disk, nothing leaves the
/// process.
final class CatGuard {
    static let shared = CatGuard()

    /// Fired on the main thread when a paw is detected.
    var onPaw: (() -> Void)?

    private let detector = PawDetector()
    private var machPort: CFMachPort?
    private var source: CFRunLoopSource?

    private(set) var isWatching = false

    private init() {
        detector.onPaw = { [weak self] in self?.onPaw?() }
    }

    private static let mask: CGEventMask = {
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        return types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
    }()

    // MARK: - Lifecycle

    /// Starts only when the user has asked for it and Accessibility is granted —
    /// it never prompts, because the guard is a background nicety and the prompt
    /// belongs to the moment the user turns it on.
    @discardableResult
    func start() -> Bool {
        guard Preferences.catGuardEnabled, EventTap.isPermitted else { return false }
        guard machPort == nil else { return true }

        detector.update(sensitivity: Preferences.catSensitivity.detectorSettings)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: CatGuard.mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let guardian = Unmanaged<CatGuard>.fromOpaque(refcon).takeUnretainedValue()
                guardian.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else { return false }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        machPort = port
        source = runLoopSource
        isWatching = true
        return true
    }

    func stop() {
        if let port = machPort {
            CGEvent.tapEnable(tap: port, enable: false)
            if let source {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            CFMachPortInvalidate(port)
        }
        machPort = nil
        source = nil
        isWatching = false
        detector.reset()
    }

    /// Re-reads the preferences: starts, stops or retunes as needed.
    func refresh() {
        if Preferences.catGuardEnabled, EventTap.isPermitted {
            if isWatching {
                detector.update(sensitivity: Preferences.catSensitivity.detectorSettings)
            } else {
                start()
            }
        } else if isWatching {
            stop()
        }
    }

    // MARK: - Callback

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = machPort { CGEvent.tapEnable(tap: port, enable: true) }
            return
        }

        let now = ProcessInfo.processInfo.systemUptime

        if type == .flagsChanged {
            let intentional: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]
            detector.modifiersChanged(active: !event.flags.intersection(intentional).isEmpty)
            return
        }

        // Auto-repeat is the keyboard talking, not the cat.
        guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        switch type {
        case .keyDown: detector.keyDown(keyCode, at: now)
        case .keyUp: detector.keyUp(keyCode)
        default: break
        }
    }
}
