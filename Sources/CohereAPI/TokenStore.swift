import Foundation

/// Persists bearer tokens keyed by account. The documented production
/// implementation is ``KeychainTokenStore``; ``InMemoryTokenStore`` exists
/// for tests and ephemeral use.
///
/// Methods are `async` so actor-isolated and Keychain-backed stores both
/// fit the same protocol.
public protocol TokenStore: Sendable {
    func read(account: String) async throws -> String?
    func write(_ token: String, account: String) async throws
    func delete(account: String) async throws
}

/// Process-lifetime token store. Tokens never reach disk — suitable for
/// tests and for apps that re-fetch on every launch. Production apps that
/// want persistence across launches use ``KeychainTokenStore``.
public actor InMemoryTokenStore: TokenStore {
    private var tokens: [String: String] = [:]

    public init() {}

    public func read(account: String) async throws -> String? {
        tokens[account]
    }

    public func write(_ token: String, account: String) async throws {
        tokens[account] = token
    }

    public func delete(account: String) async throws {
        tokens[account] = nil
    }
}
