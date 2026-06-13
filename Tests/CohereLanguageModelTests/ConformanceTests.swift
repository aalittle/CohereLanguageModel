// End-to-end conformance: drive the real executor and the full
// translator pipeline over the recorded fixtures. The executor's
// request-construction path executes on macOS 27 hosts (guarded); the
// translator scenario sweep runs everywhere.
#if compiler(>=6.4)
import Foundation
import Testing
import FoundationModels
@testable import CohereAPI
@testable import CohereLanguageModel

/// A `ChatTransport` that records the request it was handed and replays a
/// fixed byte stream. Used to assert the executor builds the right Chat V2
/// request from a transcript without any network.
final class RecordingTransport: ChatTransport, @unchecked Sendable {
    // Mutated once before the returned stream is consumed; the NSLock
    // guards the formal data race the compiler can't prove absent.
    private let lock = NSLock()
    private var _captured: ChatRequest?
    private let replay: Data

    init(replay: Data = Data()) { self.replay = replay }

    var capturedRequest: ChatRequest? {
        lock.withLock { _captured }
    }

    func stream(
        _ request: ChatRequest, baseURL: URL
    ) async throws -> AsyncThrowingStream<Data, any Error> {
        lock.withLock { _captured = request }
        let data = replay
        return AsyncThrowingStream { continuation in
            if !data.isEmpty { continuation.yield(data) }
            continuation.finish()
        }
    }
}

@Suite struct ExecutorConformanceTests {
    @available(macOS 27.0, iOS 27.0, *)
    func basicTranscript() -> Transcript {
        Transcript(entries: [
            .instructions(.init(segments: textSegments("Be terse."), toolDefinitions: [])),
            .prompt(.init(segments: textSegments("Is pump P-301 running?"))),
        ])
    }

    @Test func executorBuildsStreamingRequestFromTranscript() async throws {
        guard #available(macOS 27.0, iOS 27.0, *) else { return }
        // Empty replay → respond builds the request, captures it, and
        // returns without emitting events (nothing to drain, no blocking).
        let transport = RecordingTransport()
        let executor = CohereLanguageModelExecutor(
            configuration: .init(apiKey: "k"), transport: transport
        )
        let request = LanguageModelExecutorGenerationRequest(
            id: UUID(),
            transcript: basicTranscript(),
            enabledTools: [],
            generationOptions: GenerationOptions(temperature: 0.2),
            contextOptions: ContextOptions(),
            metadata: [:]
        )
        try await executor.respond(
            to: request,
            model: CohereLanguageModel(configuration: .init(apiKey: "k")),
            streamingInto: LanguageModelExecutorGenerationChannel()
        )

        let captured = try #require(transport.capturedRequest)
        #expect(captured.model == "command-a-plus-05-2026")
        #expect(captured.stream == true)
        #expect(captured.temperature == 0.2)
        #expect(captured.messages.count == 2)
        #expect(captured.messages.first == .system("Be terse."))
    }

    // The unsupported-transcript-content → framework-error path is proven
    // at the unit level in ErrorMapperTests (TranscriptMappingError →
    // unsupportedTranscriptContent); an executor-level repeat would only
    // add a hand-built ImageAttachment with no extra coverage.
}

/// Invariants that must hold for every streamed response, swept across all
/// recorded fixtures. These run on every host (framework-free).
@Suite struct StreamScenarioConformanceTests {
    @Test(arguments: ["chat-stream-basic", "chat-stream-citations", "chat-stream-tools"])
    func everyStreamLeadsWithMetadataAndEndsFinished(fixture: String) throws {
        let actions = try translateFixture(fixture)
        guard case .metadata = try #require(actions.first) else {
            Issue.record("\(fixture): first action must be metadata"); return
        }
        #expect(actions.last == .finished)
    }

    @Test(arguments: ["chat-stream-basic", "chat-stream-citations", "chat-stream-tools"])
    func usagePrecedesCompletion(fixture: String) throws {
        let actions = try translateFixture(fixture)
        let finishedIndex = try #require(actions.firstIndex(of: .finished))
        let hasUsage = actions[..<finishedIndex].contains {
            if case .usage = $0 { return true } else { return false }
        }
        #expect(hasUsage, "\(fixture): usage must arrive before completion")
    }

    @Test(arguments: ["chat-stream-basic", "chat-stream-citations", "chat-stream-tools"])
    func toolAndCitationPayloadsNeverLeakIntoText(fixture: String) throws {
        for case .appendText(_, let text) in try translateFixture(fixture) {
            #expect(!text.contains("equipment_id"))
            #expect(!text.contains("\"sources\""))
        }
    }
}
#endif
