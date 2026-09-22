import Foundation
import Security

/// Identifies the player by a UUID the app generates and keeps in the keychain.
///
/// Deleting the app deletes the keychain entry, which is the intended product
/// behaviour: a reinstall starts over as a new player.
///
/// That also makes the cloud copy write-only. A returning player can never read
/// their old progress back, so nothing here should be treated as a restore path
/// and no part of the UI should promise recovery.
///
/// A keychain UUID is used rather than `identifierForVendor` because IDFV only
/// resets once *every* app from the same vendor is removed — it does not match
/// "delete the app, start over" — and it is a device identifier that would have
/// to be declared as collected in the privacy manifest.
final class AnonymousIdentity {
    static let shared = AnonymousIdentity()

    private let service = "com.timefreeze.identity"
    private let playerIDAccount = "anonymousPlayerID"
    private let tokenAccount = "sessionToken"
    private let tokenExpiryAccount = "sessionTokenExpiry"

    /// Refreshed this long before the stated expiry so a request is not sent
    /// with a token that lapses mid-flight.
    private let expiryMargin: TimeInterval = 24 * 60 * 60

    private init() {}

    /// Stable for the lifetime of the install, regenerated after a reinstall.
    var playerID: String {
        if let existing = readString(account: playerIDAccount) { return existing }
        let fresh = UUID().uuidString
        writeString(fresh, account: playerIDAccount)
        return fresh
    }

    /// The current session token, or nil when absent or close to expiry.
    var validToken: String? {
        guard let token = readString(account: tokenAccount),
              let expiryText = readString(account: tokenExpiryAccount),
              let expiry = TimeInterval(expiryText) else { return nil }
        return Date().timeIntervalSince1970 + expiryMargin < expiry ? token : nil
    }

    func storeToken(_ token: String, expiresAt: TimeInterval) {
        writeString(token, account: tokenAccount)
        writeString(String(expiresAt), account: tokenExpiryAccount)
    }

    /// Called when the server rejects the token, so the next attempt re-auths.
    func clearToken() {
        delete(account: tokenAccount)
        delete(account: tokenExpiryAccount)
    }

    /// Drops the player ID along with the token, so the next launch registers as
    /// somebody new.
    ///
    /// Used by "delete cloud data": erasing the rows alone would be undone by the
    /// next sync, which would recreate them under the same ID. Rotating the ID is
    /// what makes the deletion stick, and it is the same rule the product already
    /// follows for a reinstall — a new ID is a new player.
    func forgetPlayer() {
        delete(account: playerIDAccount)
        clearToken()
    }

    // MARK: - Keychain

    private func readString(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    private func writeString(_ value: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            // Readable after the first unlock so a sync can run from the
            // background without the device being unlocked at that moment.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { _, new in new }
            return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    private func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
