import Foundation
import Testing
@testable import CohereAPI

@Suite struct TokenProviderTests {
    @Test func staticProviderReturnsItsKey() async throws {
        let provider = StaticTokenProvider("sk-test-123")
        #expect(try await provider.token() == "sk-test-123")
    }

    @Test func unauthenticatedProviderThrowsMissingCredentials() async {
        await #expect(throws: TransportError.self) {
            try await UnauthenticatedTokenProvider().token()
        }
    }

    @Test func persistingProviderRefreshesOnceThenCaches() async throws {
        let store = InMemoryTokenStore()
        let refreshCount = RefreshCounter()
        let provider = PersistingTokenProvider(account: "cohere", store: store) {
            await refreshCount.increment()
            return "fetched-token"
        }

        #expect(try await provider.token() == "fetched-token")
        #expect(try await provider.token() == "fetched-token")
        #expect(await refreshCount.value == 1)
        // Token reached the store, not just the closure's return.
        #expect(try await store.read(account: "cohere") == "fetched-token")
    }

    @Test func persistingProviderReusesAPreexistingStoredToken() async throws {
        let store = InMemoryTokenStore()
        try await store.write("already-here", account: "cohere")
        let provider = PersistingTokenProvider(account: "cohere", store: store) {
            Issue.record("refresh must not run when a token is cached")
            return "should-not-happen"
        }
        #expect(try await provider.token() == "already-here")
    }

    @Test func inMemoryStoreRoundTripsAndDeletes() async throws {
        let store = InMemoryTokenStore()
        #expect(try await store.read(account: "a") == nil)
        try await store.write("t", account: "a")
        #expect(try await store.read(account: "a") == "t")
        try await store.delete(account: "a")
        #expect(try await store.read(account: "a") == nil)
    }
}

/// Actor counter so the refresh closure stays `Sendable`.
private actor RefreshCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}
