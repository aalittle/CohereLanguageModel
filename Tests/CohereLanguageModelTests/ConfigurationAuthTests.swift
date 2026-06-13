#if compiler(>=6.4)
import Foundation
import Testing
@testable import CohereAPI
@testable import CohereLanguageModel

@Suite struct ConfigurationAuthTests {
    @Test func apiKeyConvenienceInstallsAStaticProvider() async throws {
        guard #available(macOS 27.0, iOS 27.0, *) else { return }
        let configuration = CohereLanguageModel.Configuration(apiKey: "sk-proto")
        #expect(try await configuration.tokenProvider.token() == "sk-proto")
    }

    @Test func defaultConfigurationIsUnauthenticated() async {
        guard #available(macOS 27.0, iOS 27.0, *) else { return }
        let configuration = CohereLanguageModel.Configuration()
        await #expect(throws: TransportError.self) {
            try await configuration.tokenProvider.token()
        }
    }

    @Test func tokenProviderIsExcludedFromTheCacheKey() {
        guard #available(macOS 27.0, iOS 27.0, *) else { return }
        // Same endpoint, different credentials → still one cache entry.
        let a = CohereLanguageModel.Configuration(apiKey: "key-a")
        let b = CohereLanguageModel.Configuration(apiKey: "key-b")
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test func differentEndpointsStillSplitTheCacheKey() throws {
        guard #available(macOS 27.0, iOS 27.0, *) else { return }
        let saas = CohereLanguageModel.Configuration(apiKey: "k")
        let vpc = CohereLanguageModel.Configuration(
            apiKey: "k",
            baseURL: try #require(URL(string: "https://cohere.internal.example.com"))
        )
        #expect(saas != vpc)
    }
}
#endif
