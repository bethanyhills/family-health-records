import Foundation
import Security

/// Remembers when the free trial started.
///
/// The date lives in the keychain, so deleting and reinstalling the app
/// doesn't restart the trial. It is kept on this device only (never synced),
/// and it's the only thing stored there: no health data.
enum TrialClock {
    private static let service = "com.bethanyhills.FamilyHealth.trial"
    private static let account = "trialStart"

    /// The recorded start, or `now` (saved) the first time the app runs.
    static func start(now: Date = .now) -> Date {
        if let saved = read() { return saved }
        write(now)
        return now
    }

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func read() -> Date? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let text = String(data: data, encoding: .utf8),
              let seconds = TimeInterval(text) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func write(_ date: Date) {
        var item = query
        item[kSecValueData as String] = Data(String(date.timeIntervalSince1970).utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}
