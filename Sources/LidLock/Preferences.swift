import Foundation

enum Preferences {
    private static let autoUnlockKey = "autoUnlockSeconds"
    private static let legacyAutoUnlockKey = "autoUnlockMinutes"

    /// Seconds until the lock releases itself. 0 means never.
    ///
    /// Held in seconds rather than minutes so half a minute can be offered —
    /// long enough to wipe a screen, short enough that forgetting the PIN
    /// costs nothing.
    static var autoUnlockSeconds: Int {
        get {
            if let stored = UserDefaults.standard.object(forKey: autoUnlockKey) as? Int {
                return stored
            }
            // Carried over from the versions that counted in minutes.
            if let minutes = UserDefaults.standard.object(forKey: legacyAutoUnlockKey) as? Int {
                return minutes * 60
            }
            return 60
        }
        set { UserDefaults.standard.set(newValue, forKey: autoUnlockKey) }
    }

    static let autoUnlockChoices = [30, 60, 120, 300, 600, 1800, 0]

    static func label(forSeconds seconds: Int) -> String {
        switch seconds {
        case 0: return "Never"
        case ..<60: return "\(seconds) seconds"
        case 60: return "1 minute"
        default: return "\(seconds / 60) minutes"
        }
    }

    /// Seconds of no input before the on-screen panel fades out.
    static let chromeFadeDelay: TimeInterval = 6

    // MARK: - Cat guard

    private static let catGuardKey = "catGuardEnabled"
    private static let catSensitivityKey = "catSensitivity"
    private static let catHissKey = "catHissEnabled"

    /// Off until asked for: it means watching the keyboard outside a lock.
    static var catGuardEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: catGuardKey) }
        set { UserDefaults.standard.set(newValue, forKey: catGuardKey) }
    }

    enum CatSensitivity: String, CaseIterable, Identifiable {
        case relaxed, balanced, eager

        var id: String { rawValue }

        var label: String {
            switch self {
            case .relaxed: return "Relaxed"
            case .balanced: return "Balanced"
            case .eager: return "Eager"
            }
        }

        var detail: String {
            switch self {
            case .relaxed: return "Waits for a cat to really commit. Fewest false alarms."
            case .balanced: return "Catches a cat crossing the keyboard within a step or two."
            case .eager: return "Trips on the first paw. May also trip on very fast typing."
            }
        }

        var detectorSettings: PawDetector.Sensitivity {
            switch self {
            case .relaxed: return .relaxed
            case .balanced: return .balanced
            case .eager: return .eager
            }
        }
    }

    static var catSensitivity: CatSensitivity {
        get {
            guard let raw = UserDefaults.standard.string(forKey: catSensitivityKey),
                  let value = CatSensitivity(rawValue: raw) else { return .balanced }
            return value
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: catSensitivityKey) }
    }

    /// The hiss is the half of the idea that trains the cat, so it defaults on.
    private static let meowKey = "meowEnabled"

    /// A meow as the lock lets go. Going in needs no confirmation — you asked
    /// for it — but coming out can happen on a timer, with your hands full.
    static var meowEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: meowKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: meowKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: meowKey) }
    }

    static var catHissEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: catHissKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: catHissKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: catHissKey) }
    }

    // MARK: - Lock shortcut

    private static let lockShortcutKey = "lockShortcut"

    /// The global combination that locks the screen. `nil` means the user
    /// cleared it and wants no shortcut at all, which is why a missing value
    /// and a stored null are different things here.
    static var lockShortcut: Hotkey.Shortcut? {
        get {
            guard let data = UserDefaults.standard.data(forKey: lockShortcutKey) else {
                return .lockDefault
            }
            return try? JSONDecoder().decode(Hotkey.Shortcut?.self, from: data)
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: lockShortcutKey)
        }
    }

    /// The word that releases a cat lock, in the spirit of PawSense.
    static let humanWord = "human"
}
