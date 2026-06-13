#if canImport(Security)
import Foundation
import Security

/// Keychain-backed token store (NFR-4: tokens persist in the Keychain
/// only, never in source, logs, or `UserDefaults`).
///
/// Items are generic passwords scoped to one service, accessible after
/// first unlock and not synced to iCloud — appropriate for a short-lived
/// auth token. Wrapped behind ``TokenStore`` so callers depend on the
/// protocol, not `Security` directly.
///
/// Guarded by `#if canImport(Security)` so the `CohereAPI` core still
/// compiles toward a future Linux port (NFR-3); the Keychain path is
/// Apple-only by nature.
public struct KeychainTokenStore: TokenStore {
    private let service: String
    /// Stored as `String` (the constants are toll-free-bridged `CFString`s)
    /// because `CFString` is not `Sendable`; bridged back at use.
    private let accessible: String

    /// - Parameters:
    ///   - service: Keychain service identifier; groups this app's items.
    ///   - accessible: Item accessibility. Defaults to
    ///     `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — readable
    ///     after the first unlock, never copied to other devices.
    public init(
        service: String = "com.aalittle.CohereLanguageModel",
        accessible: CFString = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    ) {
        self.service = service
        self.accessible = accessible as String
    }

    private func baseQuery(account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
    }

    public func read(account: String) async throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                let token = String(data: data, encoding: .utf8)
            else { throw KeychainError.unexpectedData }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unhandled(status)
        }
    }

    public func write(_ token: String, account: String) async throws {
        let data = Data(token.utf8)
        let addQuery = baseQuery(account: account).merging([
            kSecValueData: data,
            kSecAttrAccessible: accessible as CFString,
        ]) { _, new in new }

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let update = [kSecValueData: data] as [CFString: Any]
            let updateStatus = SecItemUpdate(
                baseQuery(account: account) as CFDictionary,
                update as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unhandled(updateStatus)
            }
        default:
            throw KeychainError.unhandled(status)
        }
    }

    public func delete(account: String) async throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }
}

/// A Keychain operation failure. `unhandled` carries the raw `OSStatus`;
/// the token value is never included in any error (NFR-4).
public enum KeychainError: Error, Equatable {
    case unexpectedData
    case unhandled(OSStatus)
}
#endif
