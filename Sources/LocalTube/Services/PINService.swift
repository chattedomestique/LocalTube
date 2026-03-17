import Foundation

// MARK: - PIN Service
//
// Stores the parental PIN and recovery phrase in UserDefaults.
//
// Rationale: This is a children's media app parental lock — not a password
// manager or banking credential.  Keychain is overkill here and, in ad-hoc
// signed SPM builds without proper entitlements, it triggers a macOS
// authorization dialog on every SecItemCopyMatching call.  UserDefaults is
// the correct tool: it's fast, requires zero permissions, and survives app
// restarts without any prompts.

enum PINService {
    private static let defaults = UserDefaults.standard
    private static let pinKey      = "lt.pin"
    private static let recoveryKey = "lt.recovery"

    // MARK: - PIN Storage

    static func savePin(_ pin: String, recoveryPhrase: String) throws {
        defaults.set(pin,            forKey: pinKey)
        defaults.set(recoveryPhrase, forKey: recoveryKey)
    }

    static func loadPin() -> String? {
        defaults.string(forKey: pinKey)
    }

    static func loadRecoveryPhrase() -> String? {
        defaults.string(forKey: recoveryKey)
    }

    static func hasPIN() -> Bool {
        loadPin() != nil
    }

    static func verify(_ input: String) -> Bool {
        guard let stored = loadPin() else { return false }
        return input == stored
    }

    static func deleteAll() throws {
        defaults.removeObject(forKey: pinKey)
        defaults.removeObject(forKey: recoveryKey)
    }

    // MARK: - Recovery Phrase Generation

    static func generateRecoveryPhrase() -> String {
        let words = loadWordlist()
        guard words.count >= 4 else { return "apple river cloud seven" }
        var selected: [String] = []
        var indices = Set<Int>()
        while selected.count < 4 {
            let i = Int.random(in: 0..<words.count)
            if indices.insert(i).inserted { selected.append(words[i]) }
        }
        return selected.joined(separator: " ")
    }

    // MARK: - Word List

    private static func loadWordlist() -> [String] {
        guard let url = Bundle.main.url(forResource: "LocalTube_LocalTube", withExtension: nil)?
                .deletingLastPathComponent()
                .appendingPathComponent("wordlist.txt"),
              let contents = try? String(contentsOf: url)
        else { return fallbackWords }
        return contents.components(separatedBy: .newlines).filter { !$0.isEmpty }
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
