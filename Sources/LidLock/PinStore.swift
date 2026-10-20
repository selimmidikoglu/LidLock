import Foundation
import CryptoKit
import Security

/// Stores the unlock PIN as a salted, iterated SHA-256 digest in the keychain.
/// The PIN itself is never persisted.
enum PinStore {
    private static let service = "com.selim.lidlock.pin"
    private static let account = "unlock-pin"
    private static let iterations = 120_000

    struct Record: Codable {
        let salt: Data
        let digest: Data
        let length: Int
        /// Digest of every prefix of the PIN, shortest first, so the lock screen
        /// can show how far a typed sequence actually matches. Absent in records
        /// written before prefix feedback existed.
        let prefixDigests: [Data]?
    }

    enum StoreError: LocalizedError {
        case keychain(OSStatus)
        case emptyPin

        var errorDescription: String? {
            switch self {
            case .keychain(let status):
                let message = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
                return "Keychain error: \(message)"
            case .emptyPin:
                return "A PIN needs at least one digit."
            }
        }
    }

    // MARK: - Derivation

    static func derive(pin: String, salt: Data) -> Data {
        var block = Data(salt)
        block.append(Data(pin.utf8))
        var digest = Data(SHA256.hash(data: block))
        for _ in 1..<iterations {
            var round = Data(salt)
            round.append(digest)
            digest = Data(SHA256.hash(data: round))
        }
        return digest
    }

    /// True when `candidate` is exactly the first `candidate.count` digits of the
    /// stored PIN. Legacy records carry no prefix digests and can only answer for
    /// the full length.
    static func matchesPrefix(_ candidate: String, record: Record) -> Bool {
        guard let expected = expectedDigest(prefixLength: candidate.count, record: record) else { return false }
        return constantTimeEqual(derive(pin: candidate, salt: record.salt), expected)
    }

    private static func expectedDigest(prefixLength length: Int, record: Record) -> Data? {
        if length == record.length { return record.digest }
        guard let prefixes = record.prefixDigests, length >= 1, length < prefixes.count else { return nil }
        return prefixes[length - 1]
    }

    private static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for (x, y) in zip(a, b) { diff |= x ^ y }
        return diff == 0
    }

    // MARK: - Persistence

    static func save(pin: String) throws {
        guard !pin.isEmpty else { throw StoreError.emptyPin }
        var salt = Data(count: 32)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        // Each derivation costs ~100 ms, so a 12-digit PIN would stall the
        // Settings window for over a second if the prefixes were done in turn.
        var digests = [Data](repeating: Data(), count: pin.count)
        let slot = NSLock()
        DispatchQueue.concurrentPerform(iterations: pin.count) { index in
            let digest = derive(pin: String(pin.prefix(index + 1)), salt: salt)
            slot.lock()
            digests[index] = digest
            slot.unlock()
        }
        let record = Record(salt: salt, digest: digests[pin.count - 1], length: pin.count, prefixDigests: digests)
        let payload = try JSONEncoder().encode(record)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = payload
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
    }

    static func load() -> Record? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
