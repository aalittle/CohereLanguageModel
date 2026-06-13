import Foundation

/// Supplies a bearer token for Chat V2 requests.
///
/// This is the documented authentication path (FR-7, and Apple's explicit
/// guidance: do not take API keys as initializer strings). Production apps
/// implement this to fetch a short-lived token from their backend — ideally
/// gated by App Attest — and persist it with ``PersistingTokenProvider``
/// backed by ``KeychainTokenStore``.
///
/// `token()` is called once per request, so an implementation is free to
/// refresh on expiry. The returned value becomes an `Authorization: Bearer`
/// header and is never logged (NFR-4).
public protocol TokenProvider: Sendable {
    func token() async throws -> String
}

/// Wraps a raw API key. **Prototyping only** — a key string in source or
/// memory is exactly what ``TokenProvider`` exists to avoid. Documented as
/// a convenience so first-run code is one line; ship real apps with a
/// fetch-and-persist provider.
public struct StaticTokenProvider: TokenProvider {
    private let value: String

    public init(_ apiKey: String) {
        self.value = apiKey
    }

    public func token() async throws -> String { value }
}

/// Used when a ``Configuration`` is built without credentials. Fails every
/// request with ``TransportError/missingCredentials`` rather than sending
/// an empty token — a clear "you must configure auth" signal.
public struct UnauthenticatedTokenProvider: TokenProvider {
    public init() {}

    public func token() async throws -> String {
        throw TransportError.missingCredentials
    }
}

/// Persists fetched tokens so the upstream `refresh` (a network call, an
/// App Attest exchange) runs only when the cache is empty.
///
/// The caching logic is storage-agnostic and pure, so it is testable
/// against an ``InMemoryTokenStore`` without touching the real Keychain.
/// In production, inject a ``KeychainTokenStore``.
public struct PersistingTokenProvider: TokenProvider {
    private let account: String
    private let store: any TokenStore
    private let refresh: @Sendable () async throws -> String

    public init(
        account: String,
        store: any TokenStore,
        refresh: @escaping @Sendable () async throws -> String
    ) {
        self.account = account
        self.store = store
        self.refresh = refresh
    }

    public func token() async throws -> String {
        if let cached = try await store.read(account: account) {
            return cached
        }
        let fresh = try await refresh()
        try await store.write(fresh, account: account)
        return fresh
    }
}
