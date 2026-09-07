import Foundation
import Security
import Swaco

/// A token pair, as OAuth hands it over.
public struct Tokens: Sendable, Hashable, Codable {
    /// The token attached to a request.
    public var access: String
    /// The token exchanged for a new pair when the access one goes stale.
    public var refresh: String?
    /// When the access token stops working, where the vendor said.
    public var expires: Date?

    public init(access: String, refresh: String? = nil, expires: Date? = nil) {
        self.access = access
        self.refresh = refresh
        self.expires = expires
    }

    /// Whether it is worth refreshing before the next request. A minute of
    /// slack, because a token that expires in flight fails the request.
    public func isStale(now: Date = Date(), slack: TimeInterval = 60) -> Bool {
        guard let expires else { return false }
        return expires.timeIntervalSince(now) <= slack
    }
}

/// Where OAuth tokens are kept.
///
/// Another contract with no default: a token is the most product-specific
/// thing there is, and where it belongs depends on whether an app shares it
/// with an extension, syncs it, or holds it for one launch. Swaco fixes the
/// shape and ships a reference implementation; the app names one.
public protocol TokenStore: Sendable {
    func tokens() async throws -> Tokens?
    func save(_ tokens: Tokens) async throws
    func clear() async throws
}

/// Tokens for as long as the process lives. What a test and a first program
/// want, and what an app should not ship.
public actor InMemoryTokenStore: TokenStore {
    private var kept: Tokens?

    public init(_ tokens: Tokens? = nil) {
        kept = tokens
    }

    public func tokens() async throws -> Tokens? { kept }
    public func save(_ tokens: Tokens) async throws { kept = tokens }
    public func clear() async throws { kept = nil }
}

/// Tokens in the Keychain, which is where a shipping app keeps them.
///
/// One generic password item, named by the app. Whether it is shared with an
/// app extension through an access group, and whether it syncs, are the app's
/// to say, so both are parameters and neither has a swaco default.
public actor KeychainTokenStore: TokenStore {
    private let service: String
    private let account: String
    private let accessGroup: String?

    /// - Parameters:
    ///   - service: how this app names the vendor these tokens are for.
    ///   - account: which account, where an app has more than one.
    ///   - accessGroup: a Keychain access group, when an app extension shares
    ///     the tokens. Nil keeps them to this app.
    public init(service: String, account: String = "default", accessGroup: String? = nil) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
    }

    public func tokens() async throws -> Tokens? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return try JSONDecoder().decode(Tokens.self, from: data)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.failed(status)
        }
    }

    public func save(_ tokens: Tokens) async throws {
        let data = try JSONEncoder().encode(tokens)
        let status = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var item = baseQuery
            item[kSecValueData as String] = data
            // Available when the device is unlocked, and never off this
            // device: a token that syncs to a backup is a token that leaks.
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError.failed(added) }
        default:
            throw KeychainError.failed(status)
        }
    }

    public func clear() async throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.failed(status)
        }
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }
}

public enum KeychainError: Error, Sendable, Equatable {
    case failed(OSStatus)
}
