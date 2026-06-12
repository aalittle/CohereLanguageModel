// Issue #3 spike: verify a minimal LanguageModel + LanguageModelExecutor
// conformance compiles against the macOS 27.0 beta SDK. No API design here.
import Foundation
import FoundationModels

@available(macOS 27.0, iOS 27.0, *)
struct SpikeCohereModel: LanguageModel {
    struct Configuration: Hashable, Sendable {
        var modelID: String = "command-a-plus-05-2026"
        var baseURL: URL = URL(string: "https://api.cohere.com")!
    }

    var configuration = Configuration()

    var capabilities: LanguageModelCapabilities {
        LanguageModelCapabilities(capabilities: [.toolCalling, .reasoning, .guidedGeneration])
    }

    var executorConfiguration: Configuration { configuration }

    typealias Executor = SpikeCohereExecutor
}

@available(macOS 27.0, iOS 27.0, *)
struct SpikeCohereExecutor: LanguageModelExecutor {
    typealias Model = SpikeCohereModel

    let configuration: Model.Configuration

    init(configuration: Model.Configuration) throws {
        self.configuration = configuration
    }

    func prewarm(model: Model, transcript: Transcript) {}

    func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: Model,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        // Recommended order: metadata first, then text.
        await channel.send(.response(action: .updateMetadata(["request_id": "spike-fixed-id"])))
        await channel.send(.response(action: .appendText("Hello from the spike.", tokenCount: 5)))
        await channel.send(.response(action: .updateUsage(
            input: .init(totalTokenCount: 1, cachedTokenCount: 0),
            output: .init(totalTokenCount: 5, reasoningTokenCount: 0)
        )))
    }
}
