import Foundation

enum Preferences {
    private static let autoUnlockKey = "autoUnlockMinutes"

    /// Minutes until the lock releases itself. 0 means never.
    static var autoUnlockMinutes: Int {
        get {
            if UserDefaults.standard.object(forKey: autoUnlockKey) == nil { return 5 }
            return UserDefaults.standard.integer(forKey: autoUnlockKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: autoUnlockKey) }
    }

    static let autoUnlockChoices = [1, 2, 5, 10, 30, 0]

    static func label(forMinutes minutes: Int) -> String {
        minutes == 0 ? "Never" : "\(minutes) minutes"
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
    static var catHissEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: catHissKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: catHissKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: catHissKey) }
    }

    private static let catPortraitKey = "catPortrait"

    enum CatPortrait: String, CaseIterable, Identifiable {
        case kitten, knight

        var id: String { rawValue }

        var label: String {
            switch self {
            case .kitten: return "Kitten"
            case .knight: return "Drawn knight"
            }
        }
    }

    /// The kitten wins when its frames are installed; a fresh checkout has none
    /// and quietly gets the drawn knight instead.
    static var catPortrait: CatPortrait {
        get {
            guard let raw = UserDefaults.standard.string(forKey: catPortraitKey),
                  let value = CatPortrait(rawValue: raw) else { return .kitten }
            return value
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: catPortraitKey) }
    }

    /// The word that releases a cat lock, in the spirit of PawSense.
    static let humanWord = "human"
}
