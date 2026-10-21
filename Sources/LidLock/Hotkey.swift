import AppKit
import Carbon.HIToolbox

/// One global hotkey, registered through Carbon.
///
/// Carbon is the only way to claim a system-wide key combination without a
/// second permission prompt — a global `NSEvent` monitor would need
/// Accessibility before the user has any reason to grant it, and the whole
/// point of the shortcut is to lock the Mac before touching anything else.
final class Hotkey {
    static let shared = Hotkey()

    /// What the user pressed, kept as the key code plus the character it typed
    /// so the shortcut can be drawn without translating key codes by hand.
    struct Shortcut: Codable, Equatable {
        var keyCode: UInt16
        var modifiers: UInt
        var label: String

        static let lockDefault = Shortcut(
            keyCode: UInt16(kVK_ANSI_L),
            modifiers: NSEvent.ModifierFlags([.control, .option, .command]).rawValue,
            label: "L"
        )

        var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

        /// `⌃⌥⌘L`, in the order macOS draws modifiers in menus.
        var display: String {
            var text = ""
            if flags.contains(.control) { text += "⌃" }
            if flags.contains(.option) { text += "⌥" }
            if flags.contains(.shift) { text += "⇧" }
            if flags.contains(.command) { text += "⌘" }
            return text + label
        }

        var carbonModifiers: UInt32 {
            var carbon: UInt32 = 0
            if flags.contains(.control) { carbon |= UInt32(controlKey) }
            if flags.contains(.option) { carbon |= UInt32(optionKey) }
            if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
            if flags.contains(.command) { carbon |= UInt32(cmdKey) }
            return carbon
        }
    }

    var onFire: (() -> Void)?

    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?

    private init() {}

    /// Claims the combination, replacing whatever was claimed before.
    /// Returns false when another app already owns it, leaving nothing
    /// registered — the caller decides what to tell the user.
    @discardableResult
    func register(_ shortcut: Shortcut?) -> Bool {
        unregister()
        guard let shortcut else { return true }
        installHandler()

        let id = EventHotKeyID(signature: OSType(0x4C_44_4C_4B), id: 1)  // 'LDLK'
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if status != noErr { reference = nil }
        return status == noErr
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, context in
                guard let context else { return noErr }
                let hotkey = Unmanaged<Hotkey>.fromOpaque(context).takeUnretainedValue()
                DispatchQueue.main.async { hotkey.onFire?() }
                return noErr
            },
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
    }
}
