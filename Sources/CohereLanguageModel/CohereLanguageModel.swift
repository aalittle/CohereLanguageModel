// The FoundationModels LanguageModel protocol exists only in the iOS 27 /
// macOS 27 SDK (Xcode 27, Swift 6.4). The compiler gate makes this module
// compile to nothing on older toolchains so the package — and CI runners
// without the beta — still build. Remove the gate once Xcode 27 is GM.
#if compiler(>=6.4)
import Foundation
import FoundationModels
import CohereAPI

/// Cohere Command models as a Foundation Models `LanguageModel`.
///
/// Use it anywhere a `SystemLanguageModel` works:
///
/// ```swift
/// let model = CohereLanguageModel()
/// let session = LanguageModelSession(model: model)
/// ```
///
/// > Privacy: this is a cloud-based model. Prompts, transcripts, and
/// > grounding documents leave the device for the configured endpoint.
@available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
public struct CohereLanguageModel: LanguageModel {
    /// Identifies one logical model endpoint.
    ///
    /// The session uses this value as the **executor cache key**: model
    /// instances with equal configurations share one executor (and its
    /// URLSession). Every stored property therefore participates in
    /// `Hashable`; adding a property that shouldn't split the cache (e.g.
    /// a token provider in #12) requires deliberately excluding it from
    /// equality and documenting why.
    public struct Configuration: Hashable, Sendable {
        /// Cohere model ID. Configuration, never hardcoded downstream —
        /// survives model deprecations (PRD dependency 4).
        public var modelID: String

        /// Chat V2 endpoint. Point at a VPC or on-prem Cohere deployment
        /// to use private installations identically to SaaS (FR-8).
        public var baseURL: URL

        public init(
            modelID: String = "command-a-plus-05-2026",
            baseURL: URL = CohereAPI.defaultBaseURL
        ) {
            self.modelID = modelID
            self.baseURL = baseURL
        }
    }

    public var configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Command A+ capabilities. `vision` is deliberately absent (image
    /// input is out of scope, PRD §8). Note: citation support has no
    /// capability flag in the framework's fixed vocabulary — citations
    /// surface through response metadata instead.
    public var capabilities: LanguageModelCapabilities {
        LanguageModelCapabilities(capabilities: [
            .toolCalling, .reasoning, .guidedGeneration,
        ])
    }

    public var executorConfiguration: Configuration { configuration }

    public typealias Executor = CohereLanguageModelExecutor
}

/// The executor behind ``CohereLanguageModel``: translates the transcript,
/// streams Chat V2 SSE, and pushes framework events into the channel.
@available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
public struct CohereLanguageModelExecutor: LanguageModelExecutor {
    public typealias Model = CohereLanguageModel

    public let configuration: Model.Configuration
    let transport: any ChatTransport

    public init(configuration: Model.Configuration) throws {
        // Credential wiring (token provider + Keychain) lands with #12;
        // until then requests fail with TransportError.missingCredentials.
        self.init(
            configuration: configuration,
            transport: URLSessionChatTransport {
                throw TransportError.missingCredentials
            }
        )
    }

    /// Test seam: inject a fixture-backed transport.
    init(configuration: Model.Configuration, transport: any ChatTransport) {
        self.configuration = configuration
        self.transport = transport
    }

    public func prewarm(model: Model, transcript: Transcript) {
        // Deliberately empty for now. prewarm is synchronous and
        // non-throwing by protocol design, so anything here must stay
        // fire-and-forget; TLS pre-connect is a candidate once #12 lands.
    }

    public func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: Model,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        let messages: [ChatMessage]
        do {
            messages = try TranscriptMapper.messages(from: request.transcript)
        } catch is TranscriptMappingError {
            throw LanguageModelError.unsupportedTranscriptContent(.init(
                unsupportedContent: [],
                debugDescription:
                    "Transcript contains segments with no Chat V2 representation"
            ))
        }

        // GenerationOptions passthrough arrives with #11; tools with #16.
        let chatRequest = ChatRequest(
            model: configuration.modelID,
            messages: messages,
            stream: true
        )

        var parser = ChatStreamParser()
        var translator = StreamTranslator()

        for try await chunk in try await transport.stream(
            chatRequest, baseURL: configuration.baseURL
        ) {
            for event in parser.feed(chunk) {
                for action in translator.translate(event) {
                    if try await perform(action, on: channel) { return }
                }
            }
        }
        for event in parser.finish() {
            for action in translator.translate(event) {
                if try await perform(action, on: channel) { return }
            }
        }
    }

    /// Replays one planned action onto the real channel. Returns `true`
    /// when the stream is complete.
    private func perform(
        _ action: StreamTranslator.Action,
        on channel: LanguageModelExecutorGenerationChannel
    ) async throws -> Bool {
        switch action {
        case .metadata(let requestID):
            await channel.send(.response(
                action: .updateMetadata(["cohere.requestID": requestID])
            ))
        case .appendText(let segmentID, let text):
            // tokenCount 0 by policy: Cohere reports no per-delta counts;
            // accurate totals arrive in the usage action at message-end.
            await channel.send(.response(
                action: .appendText(text, segmentID: segmentID, tokenCount: 0)
            ))
        case .appendReasoning(let segmentID, let text):
            await channel.send(.reasoning(
                action: .appendText(text, segmentID: segmentID, tokenCount: 0)
            ))
        case .usage(let input, let cached, let output, let reasoning):
            await channel.send(.response(action: .updateUsage(
                input: .init(totalTokenCount: input, cachedTokenCount: cached),
                output: .init(totalTokenCount: output, reasoningTokenCount: reasoning)
            )))
        case .finished:
            return true
        }
        return false
    }
}
#endif
