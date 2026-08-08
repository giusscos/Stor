import Foundation
import Security

struct ASCCredentials: Codable {
    let issuerId: String
    let keyId: String
    let privateKeyPEM: String
}

final class KeychainService {
    static let shared = KeychainService()

    private let service = "com.giusscos.Stor.asc-credentials"
    private let account = "asc-api-key"

    func save(_ credentials: ASCCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.saveFailed(status) }
    }

    func load() throws -> ASCCredentials? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status == errSecItemNotFound { return nil }
            throw KeychainError.loadFailed(status)
        }
        return try JSONDecoder().decode(ASCCredentials.self, from: data)
    }

    func delete() throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}

// MARK: - Search Ads credentials

struct SearchAdsCredentials: Codable {
    let clientId: String
    let teamId: String
    let keyId: String
    let privateKeyPEM: String
    var orgId: String
}

extension KeychainService {
    private var searchAdsAccount: String { "search-ads-api-key" }

    func saveSearchAds(_ credentials: SearchAdsCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: searchAdsAccount,
            kSecValueData: data
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.saveFailed(status) }
    }

    func loadSearchAds() throws -> SearchAdsCredentials? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: searchAdsAccount,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status == errSecItemNotFound { return nil }
            throw KeychainError.loadFailed(status)
        }
        return try JSONDecoder().decode(SearchAdsCredentials.self, from: data)
    }

    func deleteSearchAds() throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: searchAdsAccount
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let s): return "Failed to save credentials (OSStatus \(s))"
        case .loadFailed(let s): return "Failed to load credentials (OSStatus \(s))"
        case .deleteFailed(let s): return "Failed to delete credentials (OSStatus \(s))"
        }
    }
}
