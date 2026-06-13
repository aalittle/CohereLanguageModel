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
///
/// The four `SecItem*` calls sit behind an internal ``KeychainBackend``
/// seam so the status-handling policy here (duplicate → update, not-found
/// → `nil`, and so on) is unit-testable against a fake, without touching
/// the real login keychain.
public struct KeychainTokenStore: TokenStore {
    private let service: String
    /// Stored as `String` (the constants are toll-free-bridged `CFString`s)
    /// because `CFString` is not `Sendable`; bridged back at use.
    private let accessible: String
    private let backend: any KeychainBackend

    /// - Parameters:
    ///   - service: Keychain service identifier; groups this app's items.
    ///   - accessible: Item accessibility. Defaults to
    ///     `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — readable
    ///     after the first unlock, never copied to other devices.
    public init(
        service: String = "com.aalittle.CohereLanguageModel",
        accessible: CFString = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    ) {
        self.init(
            service: service,
            accessible: accessible as String,
            backend: SecItemKeychainBackend()
        )
    }

    /// Test seam: inject a fake backend to exercise the status-handling
    /// branches deterministically, with no real Keychain access.
    init(service: String, accessible: String, backend: any KeychainBackend) {
        self.service = service
        self.accessible = accessible
        self.backend = backend
    }

    public func read(account: String) async throws -> String? {
        let (status, data) = backend.copyData(service: service, account: account)
        switch status {
        case errSecSuccess:
            guard let data, let token = String(data: data, encoding: .utf8) else {
                throw KeychainError.unexpectedData
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unhandled(status)
        }
    }

    public func write(_ token: String, account: String) async throws {
        let data = Data(token.utf8)
        let status = backend.add(
            service: service, account: account, data: data, accessible: accessible
        )
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let updateStatus = backend.update(service: service, account: account, data: data)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unhandled(updateStatus)
            }
        default:
            throw KeychainError.unhandled(status)
        }
    }

    public func delete(account: String) async throws {
        let status = backend.delete(service: service, account: account)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }
}

/// The four Keychain operations ``KeychainTokenStore`` needs, abstracted so
/// the store's status-handling logic can be tested against a fake. The
/// production conformer is ``SecItemKeychainBackend``.
protocol KeychainBackend: Sendable {
    func copyData(service: String, account: String) -> (status: OSStatus, data: Data?)
    func add(service: String, account: String, data: Data, accessible: String) -> OSStatus
    func update(service: String, account: String, data: Data) -> OSStatus
    func delete(service: String, account: String) -> OSStatus
}

/// Production backend: the real Keychain via the Security framework. Holds
/// no state, so it is trivially `Sendable`.
struct SecItemKeychainBackend: KeychainBackend {
    private func baseQuery(service: String, account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
    }

    func copyData(service: String, account: String) -> (status: OSStatus, data: Data?) {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    func add(service: String, account: String, data: Data, accessible: String) -> OSStatus {
        let addQuery = baseQuery(service: service, account: account).merging([
            kSecValueData: data,
            kSecAttrAccessible: accessible as CFString,
        ]) { _, new in new }
        return SecItemAdd(addQuery as CFDictionary, nil)
    }

    func update(service: String, account: String, data: Data) -> OSStatus {
        SecItemUpdate(
            baseQuery(service: service, account: account) as CFDictionary,
            [kSecValueData: data] as CFDictionary
        )
    }

    func delete(service: String, account: String) -> OSStatus {
        SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
    }
}

/// A Keychain operation failure. `unhandled` carries the raw `OSStatus`;
/// the token value is never included in any error (NFR-4).
public enum KeychainError: Error, Equatable {
    case unexpectedData
    case unhandled(OSStatus)
}
#endif
