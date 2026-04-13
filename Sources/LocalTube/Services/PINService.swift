import Foundation
import CryptoKit

// MARK: - PIN Service
//
// C4 fix: Stores a salted SHA-256 hash of the PIN (never the PIN itself).
// UserDefaults is used instead of Keychain because ad-hoc signed SPM builds
// trigger macOS authorization dialogs with SecItemCopyMatching. Hashing the
// PIN prevents anyone reading ~/Library/Preferences/ from recovering it.

enum PINService {
    private static let defaults = UserDefaults.standard
    private static let pinHashKey   = "lt.pin.hash"
    private static let pinSaltKey   = "lt.pin.salt"
    private static let pinLengthKey = "lt.pin.length"
    private static let recoveryKey  = "lt.recovery"

    // M5 fix: Rate limiting state
    private static var failedAttempts = 0
    private static var lockoutUntil: Date?

    // MARK: - PIN Storage

    static func savePin(_ pin: String, recoveryPhrase: String) throws {
        let salt = generateSalt()
        let hash = hashPIN(pin, salt: salt)
        defaults.set(hash, forKey: pinHashKey)
        defaults.set(salt, forKey: pinSaltKey)
        defaults.set(pin.count, forKey: pinLengthKey)
        defaults.set(recoveryPhrase, forKey: recoveryKey)
        // Clear any legacy plaintext PIN
        defaults.removeObject(forKey: "lt.pin")
    }

    static func loadRecoveryPhrase() -> String? {
        defaults.string(forKey: recoveryKey)
    }

    static func hasPIN() -> Bool {
        defaults.string(forKey: pinHashKey) != nil
    }

    /// Returns the stored PIN length (for auto-commit in the entry UI), or 6 as default.
    static func storedPINLength() -> Int {
        let length = defaults.integer(forKey: pinLengthKey)
        return length > 0 ? length : 6
    }

    /// M5 fix: Returns seconds remaining in lockout, or 0 if not locked out.
    static var lockoutRemaining: TimeInterval {
        guard let until = lockoutUntil else { return 0 }
        return max(0, until.timeIntervalSinceNow)
    }

    static var isLockedOut: Bool {
        lockoutRemaining > 0
    }

    static func verify(_ input: String) -> Bool {
        // M5 fix: Enforce rate limiting
        if isLockedOut { return false }

        guard let storedHash = defaults.string(forKey: pinHashKey),
              let salt = defaults.string(forKey: pinSaltKey) else { return false }

        let valid = hashPIN(input, salt: salt) == storedHash

        if valid {
            failedAttempts = 0
            lockoutUntil = nil
        } else {
            failedAttempts += 1
            // Exponential backoff: 5s after 3 failures, 30s after 5, 5min after 8
            if failedAttempts >= 3 {
                let delay: TimeInterval
                switch failedAttempts {
                case 3...4:  delay = 5
                case 5...7:  delay = 30
                default:     delay = 300
                }
                lockoutUntil = Date().addingTimeInterval(delay)
            }
        }

        return valid
    }

    static func deleteAll() throws {
        defaults.removeObject(forKey: pinHashKey)
        defaults.removeObject(forKey: pinSaltKey)
        defaults.removeObject(forKey: pinLengthKey)
        defaults.removeObject(forKey: recoveryKey)
        defaults.removeObject(forKey: "lt.pin")
        failedAttempts = 0
        lockoutUntil = nil
    }

    // MARK: - Recovery Phrase Generation

    // L4 fix: Use 6 words instead of 4 for better entropy
    static func generateRecoveryPhrase() -> String {
        let words = loadWordlist()
        let wordCount = 6
        guard words.count >= wordCount else {
            AppLogger.error("PINService: wordlist too small (\(words.count) words), need at least \(wordCount)")
            return "apple river cloud seven garden forest"
        }
        var selected: [String] = []
        var indices = Set<Int>()
        while selected.count < wordCount {
            let i = Int.random(in: 0..<words.count)
            if indices.insert(i).inserted { selected.append(words[i]) }
        }
        return selected.joined(separator: " ")
    }

    // MARK: - Hashing

    private static func hashPIN(_ pin: String, salt: String) -> String {
        let input = Data((salt + pin).utf8)
        let digest = SHA256.hash(data: input)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func generateSalt() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Word List

    private static func loadWordlist() -> [String] {
        guard let url = Bundle.main.url(forResource: "LocalTube_LocalTube", withExtension: nil)?
                .deletingLastPathComponent()
                .appendingPathComponent("wordlist.txt"),
              let contents = try? String(contentsOf: url)
        else {
            AppLogger.error("PINService: could not load wordlist.txt, using fallback")
            return fallbackWords
        }
        let words = contents.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard !words.isEmpty else {
            AppLogger.error("PINService: wordlist.txt is empty, using fallback")
            return fallbackWords
        }
        return words
    }

    private static let fallbackWords = [
        "apple", "river", "cloud", "seven", "garden", "forest", "ocean", "stone",
        "maple", "tiger", "sunny", "window", "candle", "silver", "golden", "breeze"
    ]
}

// Keep PINError for call-site compatibility even though saves no longer throw.
enum PINError: Error, LocalizedError {
    case keychainWriteFailed(OSStatus)
    case keychainDeleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychainWriteFailed(let s):  return "Write failed: \(s)"
        case .keychainDeleteFailed(let s): return "Delete failed: \(s)"
        }
    }
}
