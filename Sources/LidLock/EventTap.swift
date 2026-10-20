import CoreGraphics
import Foundation
import ApplicationServices

/// Swallows every keyboard, trackpad and media-key event at the session level.
/// Requires Accessibility permission; the tap dies with the process, which is
/// the built-in fail-safe.
final class EventTap {
    /// Called for each digit or lowercased letter typed while the tap is active.
    var onCharacter: ((Character) -> Void)?
    /// Called for every swallowed key press.
    var onBlockedKey: (() -> Void)?
    /// Called for every swallowed trackpad or mouse event.
    var onBlockedPointer: (() -> Void)?

    private var machPort: CFMachPort?
    private var source: CFRunLoopSource?

    private static let systemDefinedEventType: UInt32 = 14 // NX_SYSDEFINED: brightness, volume, media keys

    /// AppKit's multi-touch event types. CoreGraphics declares no constants for
    /// them, but they travel through the same tap — and leaving them out is how
    /// a three-finger swipe walks straight past the shield into Mission Control.
    private static let gestureEventTypes: [UInt32] = [
        18, // NSEventTypeRotate
        19, // NSEventTypeBeginGesture
        20, // NSEventTypeEndGesture
        29, // NSEventTypeGesture
        30, // NSEventTypeMagnify
        31, // NSEventTypeSwipe
        32, // NSEventTypeSmartMagnify
        34, // NSEventTypePressure
        37, // NSEventTypeDirectTouch
    ]

    private static var mask: CGEventMask = {
        let types: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .scrollWheel,
        ]
        var mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        for raw in gestureEventTypes + [systemDefinedEventType] {
            mask |= CGEventMask(1) << CGEventMask(raw)
        }
        return mask
    }()

    static var isPermitted: Bool {
        AXIsProcessTrusted()
    }

    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    func start() -> Bool {
        guard machPort == nil else { return true }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: EventTap.mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
                return tap.handle(type: type, event: event)
            },
            userInfo: refcon
        ) else { return false }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        machPort = port
        source = runLoopSource
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
    }

    // MARK: - Callback

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables a tap it considers unresponsive. Bring it straight back,
        // otherwise the keyboard unblocks mid-cleaning.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = machPort { CGEvent.tapEnable(tap: port, enable: true) }
            return nil
        }

        switch type {
        case .keyDown:
            onBlockedKey?()
            if let character = EventTap.character(from: event) {
                onCharacter?(character)
            }
        case .keyUp, .flagsChanged:
            // The press they belong to has already been counted.
            break
        default:
            if type.rawValue == EventTap.systemDefinedEventType {
                onBlockedKey?() // brightness, volume, media keys
            } else {
                // Everything left is the trackpad or the mouse: movement,
                // scrolling, clicks and the whole multi-touch family.
                onBlockedPointer?()
            }
        }

        return nil // swallow everything
    }

    private static func character(from event: CGEvent) -> Character? {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &buffer)
        guard length == 1, let scalar = Unicode.Scalar(buffer[0]) else { return nil }
        let character = Character(scalar)
        guard character.isASCII else { return nil }
        if character.isNumber { return character }
        return character.isLetter ? Character(character.lowercased()) : nil
    }
}
