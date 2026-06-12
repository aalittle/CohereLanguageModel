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

/// The executor behind ``CohereLanguageModel``. Streaming generation lands
/// with #10; until then `respond` throws ``NotImplementedYet``.
@available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
public struct CohereLanguageModelExecutor: LanguageModelExecutor {
    public typealias Model = CohereLanguageModel

    public let configuration: Model.Configuration

    public init(configuration: Model.Configuration) throws {
        self.configuration = configuration
    }

    public func prewarm(model: Model, transcript: Transcript) {
        // Connection warmup (TLS handshake via the shared URLSession)
        // arrives with the transport in #10. prewarm is synchronous and
        // non-throwing by protocol design, so it must stay fire-and-forget.
    }

    public func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: Model,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        throw NotImplementedYet()
    }

    /// Placeholder until #10. Deliberately not a `LanguageModelError`:
    /// those describe model/service failures, not missing code.
    public struct NotImplementedYet: Error {}
}
#endif
