// Adapter tests only build under the Xcode 27 beta toolchain (Swift 6.4);
// on older toolchains this file compiles to nothing, same as the module
// under test. See CLAUDE.md.
//
// Swift Testing does not allow @available on @Test, so each test guards at
// runtime instead: on hosts below macOS 27 these compile (which is itself
// the conformance check that matters most pre-GM) but execute as no-ops.
// They run for real on a macOS 27 host.
#if compiler(>=6.4)
import Foundation
import Testing
import FoundationModels
@testable import CohereLanguageModel

@Suite struct ConfigurationTests {
    @Test func defaultsTargetFlagshipModelOnSaaS() {
        guard #available(macOS 27.0, iOS 27.0, *) else { return }
        let configuration = CohereLanguageModel.Configuration()
        #expect(configuration.modelID == "command-a-plus-05-2026")
        #expect(configuration.baseURL.absoluteString == "https://api.cohere.com")
    }

    @Test func equalConfigurationsShareAnExecutorCacheKey() {
        guard #available(macOS 27.0, iOS 27.0, *) else { return }
        #expect(
            CohereLanguageModel.Configuration().hashValue
                == CohereLanguageModel.Configuration().hashValue
        )
        #expect(CohereLanguageModel.Configuration() == CohereLanguageModel.Configuration())
    }

    @Test func differingModelIDSplitsTheCacheKey() {
        guard #available(macOS 27.0, iOS 27.0, *) else { return }
        let a = CohereLanguageModel.Configuration(modelID: "command-a-plus-05-2026")
        let b = CohereLanguageModel.Configuration(modelID: "command-r7b-12-2024")
        #expect(a != b)
    }

    @Test func differingBaseURLSplitsTheCacheKey() throws {
        guard #available(macOS 27.0, iOS 27.0, *) else { return }
        let vpc = CohereLanguageModel.Configuration(
            baseURL: try #require(URL(string: "https://cohere.internal.example.com"))
        )
        #expect(vpc != CohereLanguageModel.Configuration())
    }

    @Test func modelExposesItsConfigurationAsExecutorConfiguration() {
        guard #available(macOS 27.0, iOS 27.0, *) else { return }
        let configuration = CohereLanguageModel.Configuration(modelID: "command-a-03-2025")
        let model = CohereLanguageModel(configuration: configuration)
        #expect(model.executorConfiguration == configuration)
    }

    @Test func capabilitiesDeclareToolsReasoningAndGuidedGeneration() {
        guard #available(macOS 27.0, iOS 27.0, *) else { return }
        let capabilities = CohereLanguageModel().capabilities
        #expect(capabilities.contains(.toolCalling))
        #expect(capabilities.contains(.reasoning))
        #expect(capabilities.contains(.guidedGeneration))
        #expect(!capabilities.contains(.vision))
    }

    @Test func executorInitializesFromConfiguration() throws {
        guard #available(macOS 27.0, iOS 27.0, *) else { return }
        let configuration = CohereLanguageModel.Configuration()
        let executor = try CohereLanguageModelExecutor(configuration: configuration)
        #expect(executor.configuration == configuration)
    }
}
#endif
