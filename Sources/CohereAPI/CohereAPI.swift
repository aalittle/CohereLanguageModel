import Foundation

/// Cohere Chat V2 client core: wire types, SSE stream parsing, and HTTP
/// transport. This module is pure Foundation and platform-portable; the
/// FoundationModels adapter lives in the `CohereLanguageModel` module.
///
/// Wire types land with issue #6; the SSE parser with issue #7.
public enum CohereAPI {
    /// Default Cohere SaaS endpoint. Private deployments override this
    /// via configuration (FR-8).
    public static let defaultBaseURL = URL(string: "https://api.cohere.com")!
}
