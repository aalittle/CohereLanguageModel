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
    /// URLSession).
    ///
    /// Equality and hashing cover `modelID` and `baseURL` only — the
    /// `tokenProvider` is deliberately excluded. The cache key identifies
    /// a logical *endpoint*; the provider is a credential source for that
    /// endpoint, not part of its identity. Two models pointed at the same
    /// model + URL therefore share an executor and connection pool
    /// regardless of how each fetches tokens.
    ///
    /// > Important: A consequence is that within one process, the executor
    /// > captures the provider from whichever equal configuration created
    /// > it first. For per-user credential isolation, give each tenant a
    /// > distinct `baseURL` (or otherwise distinct configuration) so they
    /// > do not collapse to one cache entry.
    public struct Configuration: Hashable, Sendable {
        /// Cohere model ID. Configuration, never hardcoded downstream —
        /// survives model deprecations (PRD dependency 4).
        public var modelID: String

        /// Chat V2 endpoint. Point at a VPC or on-prem Cohere deployment
        /// to use private installations identically to SaaS (FR-8).
        public var baseURL: URL

        /// Supplies the bearer token for each request (FR-7). Defaults to
        /// ``UnauthenticatedTokenProvider``, so a `Configuration` built
        /// without credentials constructs fine but fails requests with a
        /// clear error until a provider is set.
        public var tokenProvider: any TokenProvider

        public init(
            modelID: String = "command-a-plus-05-2026",
            baseURL: URL = CohereAPI.defaultBaseURL,
            tokenProvider: any TokenProvider = UnauthenticatedTokenProvider()
        ) {
            self.modelID = modelID
            self.baseURL = baseURL
            self.tokenProvider = tokenProvider
        }

        /// Convenience for prototyping: configure with a raw API key.
        /// The documented production path is a `tokenProvider` that fetches
        /// and persists tokens (see ``TokenProvider``); a key string in
        /// source is exactly what that path avoids.
        public init(
            apiKey: String,
            modelID: String = "command-a-plus-05-2026",
            baseURL: URL = CohereAPI.defaultBaseURL
        ) {
            self.init(
                modelID: modelID,
                baseURL: baseURL,
                tokenProvider: StaticTokenProvider(apiKey)
            )
        }

        public static func == (lhs: Configuration, rhs: Configuration) -> Bool {
            lhs.modelID == rhs.modelID && lhs.baseURL == rhs.baseURL
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(modelID)
            hasher.combine(baseURL)
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
        // The token provider is fetched per request, never stored here, so
        // a token never lives longer than one call (NFR-4).
        let tokenProvider = configuration.tokenProvider
        self.init(
            configuration: configuration,
            transport: URLSessionChatTransport {
                try await tokenProvider.token()
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
        do {
            try await stream(request, into: channel)
        } catch {
            throw ErrorMapper.mapped(error)
        }
    }

    private func stream(
        _ request: LanguageModelExecutorGenerationRequest,
        into channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        // Tools pass through with #16.
        var chatRequest = ChatRequest(
            model: configuration.modelID,
            messages: try TranscriptMapper.messages(from: request.transcript),
            stream: true
        )
        try OptionsMapper.apply(request.generationOptions, to: &chatRequest)

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
