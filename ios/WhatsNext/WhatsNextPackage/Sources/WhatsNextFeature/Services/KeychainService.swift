import Foundation
import Security

/// Secure storage service using iOS Keychain
actor KeychainService {
    static let shared = KeychainService()

    private init() {}

    enum KeychainError: LocalizedError {
        case itemNotFound
        case duplicateItem
        case invalidData
        case unhandledError(status: OSStatus)

        var errorDescription: String? {
            switch self {
            case .itemNotFound:
                return "Item not found in Keychain"
            case .duplicateItem:
                return "Item already exists in Keychain"
            case .invalidData:
                return "Invalid data format"
            case .unhandledError(let status):
                return "Keychain error: \(status)"
            }
        }
    }

    // MARK: - Generic Storage

    /// Save data to Keychain
    func save(data: Data, key: String, service: String = Bundle.main.bundleIdentifier ?? "com.gauntletai.whatsnext") throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        // Try to add
        var status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            // Item exists, update it
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key
            ]

            let updateAttributes: [String: Any] = [
                kSecValueData as String: data
            ]

            status = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
        }

        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    /// Retrieve data from Keychain
    func retrieve(key: String, service: String = Bundle.main.bundleIdentifier ?? "com.gauntletai.whatsnext") throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            throw status == errSecItemNotFound ? KeychainError.itemNotFound : KeychainError.unhandledError(status: status)
        }

        guard let data = result as? Data else {
            throw KeychainError.invalidData
        }

        return data
    }

    /// Delete data from Keychain
    func delete(key: String, service: String = Bundle.main.bundleIdentifier ?? "com.gauntletai.whatsnext") throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    // MARK: - String Convenience

    /// Save string to Keychain
    func saveString(_ string: String, key: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        try save(data: data, key: key)
    }

    /// Retrieve string from Keychain
    func retrieveString(key: String) throws -> String {
        let data = try retrieve(key: key)
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return string
    }

    // MARK: - Google OAuth Token Storage

    private let googleAccessTokenKey = "google_access_token"
    private let googleRefreshTokenKey = "google_refresh_token"
    private let googleTokenExpiryKey = "google_token_expiry"

    /// Save Google OAuth tokens securely
    func saveGoogleTokens(accessToken: String, refreshToken: String, expiresAt: Date) throws {
        try saveString(accessToken, key: googleAccessTokenKey)
        try saveString(refreshToken, key: googleRefreshTokenKey)

        let expiryString = ISO8601DateFormatter().string(from: expiresAt)
        try saveString(expiryString, key: googleTokenExpiryKey)
    }

    /// Retrieve Google OAuth tokens
    func retrieveGoogleTokens() throws -> (accessToken: String, refreshToken: String, expiresAt: Date) {
        let accessToken = try retrieveString(key: googleAccessTokenKey)
        let refreshToken = try retrieveString(key: googleRefreshTokenKey)
        let expiryString = try retrieveString(key: googleTokenExpiryKey)

        guard let expiresAt = ISO8601DateFormatter().date(from: expiryString) else {
            throw KeychainError.invalidData
        }

        return (accessToken, refreshToken, expiresAt)
    }

    /// Update Google access token (after refresh)
    func updateGoogleAccessToken(_ accessToken: String, expiresAt: Date) throws {
        try saveString(accessToken, key: googleAccessTokenKey)

        let expiryString = ISO8601DateFormatter().string(from: expiresAt)
        try saveString(expiryString, key: googleTokenExpiryKey)
    }

    /// Delete all Google tokens
    func deleteGoogleTokens() throws {
        try? delete(key: googleAccessTokenKey)
        try? delete(key: googleRefreshTokenKey)
        try? delete(key: googleTokenExpiryKey)
    }

    /// Check if Google tokens exist
    func hasGoogleTokens() -> Bool {
        do {
            _ = try retrieveString(key: googleAccessTokenKey)
            return true
        } catch {
            return false
        }
    }
}
