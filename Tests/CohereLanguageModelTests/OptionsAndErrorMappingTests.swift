// GenerationOptions.samplingMode.kind and LanguageModelError are 27-only
// at runtime, so these guard like ConfigurationTests: compile-checked
// everywhere, executed on macOS 27 hosts.
#if compiler(>=6.4)
import Foundation
import Testing
import FoundationModels
@testable import CohereAPI
@testable import CohereLanguageModel

@Suite struct OptionsMapperTests {
    func makeRequest() -> ChatRequest {
        ChatRequest(model: "m", messages: [.user("hi")], stream: true)
    }

    @Test func unsetOptionsLeaveServerDefaults() throws {
        guard #available(macOS 27.0, iOS 27.0, *) else { return }
        var request = makeRequest()
        try OptionsMapper.apply(GenerationOptions(), to: &request)
        #expect(request.temperature == nil)
        #expect(request.maxTokens == nil)
        #expect(request.k == nil)
        #expect(request.p == nil)
        #expect(request.seed == nil)
    }

    @Test func temperatureAndMaxTokensPassThrough() throws {
        guard #available(macOS 27.0, iOS 27.0, *) else { return }
        var request = makeRequest()
        try OptionsMapper.apply(
            GenerationOptions(temperature: 0.3, maximumResponseTokens: 512),
            to: &request
        )
        #expect(request.temperature == 0.3)
        #expect(request.maxTokens == 512)
    }

    @Test func topKSamplingMapsToKAndSeed() throws {
        guard #available(macOS 27.0, iOS 27.0, *) else { return }
        var request = makeRequest()
        try OptionsMapper.apply(
            GenerationOptions(samplingMode: .random(top: 40, seed: 7)),
            to: &request
        )
        #expect(request.k == 40)
        #expect(request.seed == 7)
        #expect(request.p == nil)
    }

    @Test func nucleusSamplingMapsToPAndSeed() throws {
        guard #available(macOS 27.0, iOS 27.0, *) else { return }
        var request = makeRequest()
        try OptionsMapper.apply(
            GenerationOptions(samplingMode: .random(probabilityThreshold: 0.9, seed: 7)),
            to: &request
        )
        #expect(request.p == 0.9)
        #expect(request.seed == 7)
        #expect(request.k == nil)
    }

    @Test func greedyMapsToTopOne() throws {
        guard #available(macOS 27.0, iOS 27.0, *) else { return }
        var request = makeRequest()
        try OptionsMapper.apply(GenerationOptions(samplingMode: .greedy), to: &request)
        #expect(request.k == 1)
    }

    @Test func requiredToolCallingThrowsRatherThanApproximating() {
        guard #available(macOS 27.0, iOS 27.0, *) else { return }
        var request = makeRequest()
        #expect(throws: LanguageModelError.self) {
            try OptionsMapper.apply(
                GenerationOptions(toolCallingMode: .required), to: &request
            )
        }
    }

    @Test func seedBitPatternIsStable() {
        guard #available(macOS 27.0, iOS 27.0, *) else { return }
        // Equal seeds map equal — determinism survives the UInt64→Int trip.
        #expect(OptionsMapper.seedValue(.max) == OptionsMapper.seedValue(.max))
        #expect(OptionsMapper.seedValue(42) == 42)
    }
}

@Suite struct ErrorMapperTests {
    @Test func rateLimitMapsWithResetDate() throws {
        guard #available(macOS 27.0, iOS 27.0, *) else { return }
        let reset = Date(timeIntervalSinceNow: 30)
        let mapped = ErrorMapper.mapped(TransportError.httpError(
            statusCode: 429,
            body: .init(id: nil, message: "rate limited"),
            retryAfter: reset
        ))
        guard case LanguageModelError.rateLimited(let info) = mapped else {
            Issue.record("expected rateLimited, got \(mapped)"); return
        }
        #expect(info.resetDate == reset)
    }

    @Test func quotaExhausted429WithoutRetryAfterMapsWithNilReset() throws {
        guard #available(macOS 27.0, iOS 27.0, *) else { return }
        // The real-world case observed in #4.
        let mapped = ErrorMapper.mapped(TransportError.httpError(
            statusCode: 429,
            body: .init(id: nil, message: "Trial key limited to 1000 calls / month"),
            retryAfter: nil
        ))
        guard case LanguageModelError.rateLimited(let info) = mapped else {
            Issue.record("expected rateLimited, got \(mapped)"); return
        }
        #expect(info.resetDate == nil)
        #expect(info.debugDescription.contains("1000"))
    }

    @Test func tokenOverflow400MapsToContextSizeExceeded() throws {
        guard #available(macOS 27.0, iOS 27.0, *) else { return }
        let mapped = ErrorMapper.mapped(TransportError.httpError(
            statusCode: 400,
            body: .init(id: nil, message: "too many tokens: max 128000"),
            retryAfter: nil
        ))
        guard case LanguageModelError.contextSizeExceeded = mapped else {
            Issue.record("expected contextSizeExceeded, got \(mapped)"); return
        }
    }

    @Test func badRequest400WithoutTokenHintStaysTransportError() throws {
        guard #available(macOS 27.0, iOS 27.0, *) else { return }
        let mapped = ErrorMapper.mapped(TransportError.httpError(
            statusCode: 400,
            body: .init(id: nil, message: "invalid request: unknown field"),
            retryAfter: nil
        ))
        guard case TransportError.httpError(let status, _, _) = mapped else {
            Issue.record("developer errors must stay TransportError"); return
        }
        #expect(status == 400)
    }

    @Test func urlTimeoutMapsToTimeout() throws {
        guard #available(macOS 27.0, iOS 27.0, *) else { return }
        let mapped = ErrorMapper.mapped(URLError(.timedOut))
        guard case LanguageModelError.timeout = mapped else {
            Issue.record("expected timeout, got \(mapped)"); return
        }
    }

    @Test func transcriptMappingErrorMapsToUnsupportedContent() throws {
        guard #available(macOS 27.0, iOS 27.0, *) else { return }
        let mapped = ErrorMapper.mapped(
            TranscriptMappingError.unsupportedSegment(entryID: "e", segmentID: "s")
        )
        guard case LanguageModelError.unsupportedTranscriptContent = mapped else {
            Issue.record("expected unsupportedTranscriptContent, got \(mapped)"); return
        }
    }

    @Test func authFailuresPassThroughUnmapped() throws {
        guard #available(macOS 27.0, iOS 27.0, *) else { return }
        let mapped = ErrorMapper.mapped(TransportError.httpError(
            statusCode: 401, body: nil, retryAfter: nil
        ))
        guard case TransportError.httpError = mapped else {
            Issue.record("401 must stay TransportError"); return
        }
    }
}
#endif
