import Foundation
import Security

struct ASCCredentials: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    let issuerId: String
    let keyId: String
    let privateKeyPEM: String

    init(
        id: UUID = UUID(),
        name: String = "App Store Connect",
        issuerId: String,
        keyId: String,
        privateKeyPEM: String
    ) {
        self.id = id
        self.name = name
        self.issuerId = issuerId
        self.keyId = keyId
        self.privateKeyPEM = privateKeyPEM
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "App Store Connect"
        issuerId = try container.decode(String.self, forKey: .issuerId)
        keyId = try container.decode(String.self, forKey: .keyId)
        privateKeyPEM = try container.decode(String.self, forKey: .privateKeyPEM)
    }

    var shortKeyId: String {
        keyId.count > 6 ? String(keyId.prefix(6)) + "…" : keyId
    }
}

struct ASCAccountStore: Codable {
    var accounts: [ASCCredentials]
    var activeAccountId: UUID?

    var active: ASCCredentials? {
        if let activeAccountId,
           let match = accounts.first(where: { $0.id == activeAccountId }) {
            return match
        }
        return accounts.first
    }
}

final class KeychainService {
    static let shared = KeychainService()

    private let service = "com.giusscos.Stor.asc-credentials"
    private let account = "asc-api-key"

    // MARK: - Active credential (backwards-compatible)

    func save(_ credentials: ASCCredentials) throws {
        var store = (try? loadStore()) ?? ASCAccountStore(accounts: [], activeAccountId: nil)
        if let index = store.accounts.firstIndex(where: {
            $0.id == credentials.id || ($0.issuerId == credentials.issuerId && $0.keyId == credentials.keyId)
        }) {
            var updated = credentials
            updated.id = store.accounts[index].id
            store.accounts[index] = updated
            store.activeAccountId = updated.id
        } else {
            store.accounts.append(credentials)
            store.activeAccountId = credentials.id
        }
        try saveStore(store)
    }

    func load() throws -> ASCCredentials? {
        try loadStore()?.active
    }

    func delete() throws {
        try deleteKeychainItem()
    }

    // MARK: - Multi-account

    func loadStore() throws -> ASCAccountStore? {
        guard let data = try readKeychainData() else { return nil }

        if let store = try? JSONDecoder().decode(ASCAccountStore.self, from: data),
           !store.accounts.isEmpty || dataContainsAccountStore(data) {
            return store.accounts.isEmpty ? nil : normalized(store)
        }

        // Legacy single-credential payload
        if let legacy = try? JSONDecoder().decode(ASCCredentials.self, from: data) {
            let store = ASCAccountStore(accounts: [legacy], activeAccountId: legacy.id)
            try? saveStore(store)
            return store
        }

        return nil
    }

    func saveStore(_ store: ASCAccountStore) throws {
        let normalizedStore = normalized(store)
        let data = try JSONEncoder().encode(normalizedStore)
        try writeKeychainData(data)
    }

    func allAccounts() throws -> [ASCCredentials] {
        try loadStore()?.accounts ?? []
    }

    func setActiveAccount(id: UUID) throws {
        var store = try loadStore() ?? ASCAccountStore(accounts: [], activeAccountId: nil)
        guard store.accounts.contains(where: { $0.id == id }) else { return }
        store.activeAccountId = id
        try saveStore(store)
    }

    func removeAccount(id: UUID) throws -> ASCCredentials? {
        var store = try loadStore() ?? ASCAccountStore(accounts: [], activeAccountId: nil)
        store.accounts.removeAll { $0.id == id }
        if store.accounts.isEmpty {
            try deleteKeychainItem()
            return nil
        }
        if store.activeAccountId == id {
            store.activeAccountId = store.accounts.first?.id
        }
        try saveStore(store)
        return store.active
    }

    // MARK: - Keychain I/O

    private func readKeychainData() throws -> Data? {
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
        return data
    }

    private func writeKeychainData(_ data: Data) throws {
        try KeychainService.write(data, service: service, account: account)
    }

    /// Signing keys are device-bound on purpose: `ThisDeviceOnly` keeps the `.p8` out of
    /// iCloud Keychain so it cannot propagate to the user's other machines.
    fileprivate static func write(_ data: Data, service: String, account: String) throws {
        let identity: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(identity as CFDictionary)

        var attributes = identity
        attributes[kSecValueData] = data
        attributes[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        attributes[kSecAttrSynchronizable] = false

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.saveFailed(status) }
    }

    private func deleteKeychainItem() throws {
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

    private func normalized(_ store: ASCAccountStore) -> ASCAccountStore {
        var copy = store
        if copy.activeAccountId == nil || !copy.accounts.contains(where: { $0.id == copy.activeAccountId }) {
            copy.activeAccountId = copy.accounts.first?.id
        }
        return copy
    }

    private func dataContainsAccountStore(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return json["accounts"] != nil
    }
}

// MARK: - Search Ads credentials

struct SearchAdsCredentials: Codable {
    let clientId: String
    let teamId: String
    let keyId: String
    let privateKeyPEM: String
    var orgId: String

    /// Identifies which account an issued token belongs to, without including the key itself.
    var cacheIdentity: String { "\(clientId)|\(teamId)|\(keyId)|\(orgId)" }
}

extension KeychainService {
    private var searchAdsAccount: String { "search-ads-api-key" }

    func saveSearchAds(_ credentials: SearchAdsCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        try KeychainService.write(data, service: service, account: searchAdsAccount)
        SearchAdsAPIClient.shared.invalidateToken()
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
        SearchAdsAPIClient.shared.invalidateToken()
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
