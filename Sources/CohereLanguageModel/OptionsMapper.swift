#if compiler(>=6.4)
import Foundation
import FoundationModels
import CohereAPI

/// Maps developer intent (`GenerationOptions`) onto Chat V2 request
/// parameters (FR-5). Only explicitly-set options are sent; everything
/// else stays `nil` so Cohere's server defaults apply.
///
/// | Apple | Cohere |
/// |---|---|
/// | `temperature` | `temperature` |
/// | `maximumResponseTokens` | `max_tokens` |
/// | `samplingMode.kind == .greedy` | `k: 1` (documented approximation) |
/// | `.top(k:seed:)` | `k` + `seed` |
/// | `.nucleus(threshold:seed:)` | `p` + `seed` |
/// | `toolCallingMode` | handled with tools in #16; `.required` throws |
@available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
enum OptionsMapper {
    static func apply(
        _ options: GenerationOptions, to request: inout ChatRequest
    ) throws {
        request.temperature = options.temperature
        request.maxTokens = options.maximumResponseTokens

        if let kind = options.samplingMode?.kind {
            switch kind {
            case .greedy:
                // Cohere has no explicit greedy switch; top-1 sampling is
                // the honest equivalent.
                request.k = 1
            case .top(let k, let seed):
                request.k = k
                request.seed = seed.map(Self.seedValue)
            case .nucleus(let threshold, let seed):
                request.p = threshold
                request.seed = seed.map(Self.seedValue)
            @unknown default:
                throw LanguageModelError.unsupportedCapability(.init(
                    capability: .guidedGeneration,
                    debugDescription: "Unrecognized sampling mode cannot be sent to Cohere"
                ))
            }
        }

        if options.toolCallingMode == .required {
            // Chat V2 has no way to *force* a tool call. Approximating
            // "required" as "allowed" would silently violate developer
            // intent, so this throws instead (FR-5).
            throw LanguageModelError.unsupportedCapability(.init(
                capability: .toolCalling,
                debugDescription: "Cohere cannot guarantee a tool call (toolCallingMode: .required)"
            ))
        }
    }

    /// Apple seeds are `UInt64`; Cohere's wire format is a signed int.
    /// The bit pattern is preserved (`truncatingIfNeeded`) so equal Apple
    /// seeds always map to equal Cohere seeds — determinism survives even
    /// though the numeric value may differ.
    static func seedValue(_ seed: UInt64) -> Int {
        Int(truncatingIfNeeded: seed)
    }
}
#endif
