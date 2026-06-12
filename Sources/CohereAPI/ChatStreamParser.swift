import Foundation
#if canImport(os)
import os
#endif

/// Combines SSE framing and event decoding: feed raw network bytes, get
/// typed ``ChatStreamEvent`` values.
///
/// Per NFR-5, a payload that fails to decode is skipped with a debug log —
/// one malformed event must not kill an otherwise healthy stream. Unknown
/// event types pass through as ``ChatStreamEvent/unknown(type:)`` so callers
/// can observe them; they carry no payload to misinterpret.
public struct ChatStreamParser: Sendable {
    private var sse = SSEParser()

    #if canImport(os)
    private static let logger = Logger(
        subsystem: "com.aalittle.CohereLanguageModel", category: "ChatStreamParser"
    )
    #endif

    public init() {}

    public mutating func feed(_ chunk: Data) -> [ChatStreamEvent] {
        sse.feed(chunk).compactMap(Self.decodePayload)
    }

    /// Flush a final unterminated event after the stream closes.
    public mutating func finish() -> [ChatStreamEvent] {
        sse.finish().compactMap(Self.decodePayload)
    }

    private static func decodePayload(_ payload: String) -> ChatStreamEvent? {
        do {
            return try ChatStreamEventDecoder.decode(Data(payload.utf8))
        } catch {
            // Payload content is deliberately not logged: it can contain
            // user prompt/response text (privacy) — the error alone is safe.
            #if canImport(os)
            logger.debug("Skipping undecodable SSE event: \(String(describing: error), privacy: .public)")
            #endif
            return nil
        }
    }
}
