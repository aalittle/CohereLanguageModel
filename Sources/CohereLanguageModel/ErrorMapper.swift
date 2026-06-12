#if compiler(>=6.4)
import Foundation
import FoundationModels
import CohereAPI

/// Maps transport and mapping failures onto the framework's built-in
/// `LanguageModelError` cases (FR-6). Per the #3 spike finding, the
/// built-in vocabulary covers everything observed from Cohere — adding a
/// custom error case requires written justification.
///
/// Errors with no built-in equivalent (e.g. authentication failures,
/// which developers must fix rather than handle) pass through unchanged
/// as `TransportError`.
@available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
enum ErrorMapper {
    static func mapped(_ error: any Error) -> any Error {
        switch error {
        case let TransportError.httpError(statusCode, body, retryAfter):
            return mapped(statusCode: statusCode, body: body, retryAfter: retryAfter)
        case is TranscriptMappingError:
            return LanguageModelError.unsupportedTranscriptContent(.init(
                unsupportedContent: [],
                debugDescription:
                    "Transcript contains segments with no Chat V2 representation"
            ))
        case let urlError as URLError where urlError.code == .timedOut:
            return LanguageModelError.timeout(.init(
                debugDescription: "Request to Cohere timed out"
            ))
        default:
            return error
        }
    }

    private static func mapped(
        statusCode: Int, body: APIErrorBody?, retryAfter: Date?
    ) -> any Error {
        let message = body?.message ?? "HTTP \(statusCode)"
        switch statusCode {
        case 429:
            // Observed in #4: quota-exhausted 429s carry no Retry-After,
            // so a nil resetDate is a real-world case, not a bug.
            return LanguageModelError.rateLimited(.init(
                resetDate: retryAfter, debugDescription: message
            ))
        case 400, 422:
            // Cohere reports context overflow as a 4xx whose message
            // mentions token counts; it does not echo the limits, so
            // they're zero here and the message carries the detail.
            // Other 4xx bodies (bad request shapes) stay TransportError —
            // those are developer bugs, not model conditions.
            if message.lowercased().contains("token") {
                return LanguageModelError.contextSizeExceeded(.init(
                    contextSize: 0, tokenCount: 0, debugDescription: message
                ))
            }
            return TransportError.httpError(
                statusCode: statusCode, body: body, retryAfter: retryAfter
            )
        case 408, 504:
            return LanguageModelError.timeout(.init(debugDescription: message))
        default:
            return TransportError.httpError(
                statusCode: statusCode, body: body, retryAfter: retryAfter
            )
        }
    }
}
#endif
