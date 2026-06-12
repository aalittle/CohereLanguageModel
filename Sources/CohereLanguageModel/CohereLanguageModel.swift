/// The Foundation Models adapter for Cohere Command models.
///
/// This module will provide `CohereLanguageModel` (a `LanguageModel`
/// conformance, issue #8) and its executor (issue #10). It depends on the
/// iOS 27 / macOS 27 SDK; adapter types are availability-annotated rather
/// than raising the package's platform floor, so `CohereAPI` stays
/// buildable on stock toolchains.
///
/// The FoundationModels import arrives with issue #8.
import CohereAPI
