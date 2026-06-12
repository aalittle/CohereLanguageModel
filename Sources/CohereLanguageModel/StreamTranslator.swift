#if compiler(>=6.4)
import Foundation
import CohereAPI

/// The translation policy from Cohere stream events to planned framework
/// actions — kept framework-free so it is fully unit-testable on hosts
/// where the 27-only channel types cannot be constructed. The executor
/// replays ``Action`` values onto the real generation channel.
///
/// Token-count policy (decided in #4/#10): Cohere reports no per-delta
/// token counts, so every fragment carries `tokenCount: 0` and the
/// accurate totals arrive in one ``Action/usage(_:)`` at message-end.
/// Usage therefore arrives *late* relative to Apple's recommended order —
/// a documented deviation (FR-14).
struct StreamTranslator {
    enum Action: Equatable {
        /// Emit before any text: request ID for logging/correlation.
        case metadata(requestID: String)
        case appendText(segmentID: String, text: String)
        case appendReasoning(segmentID: String, text: String)
        case usage(
            inputTokens: Int, cachedTokens: Int,
            outputTokens: Int, reasoningTokens: Int
        )
        case finished
    }

    /// Indices of content blocks currently streaming as `thinking`.
    private var thinkingIndices: Set<Int> = []

    /// Maps one stream event to zero or more planned actions.
    /// Citation and tool events are intentionally not translated in v1
    /// (they land with #18 and #16); unknown events pass through silently
    /// per NFR-5 — the parser already logged them.
    mutating func translate(_ event: ChatStreamEvent) -> [Action] {
        switch event {
        case .messageStart(let id):
            return id.map { [.metadata(requestID: $0)] } ?? []
        case .contentStart(let index, let block):
            if case .thinking = block { thinkingIndices.insert(index) }
            return []
        case .contentDelta(let index, .text(let text)):
            return [.appendText(segmentID: segmentID(index), text: text)]
        case .contentDelta(let index, .thinking(let text)):
            return [.appendReasoning(segmentID: segmentID(index), text: text)]
        case .toolPlanDelta(let text):
            return [.appendReasoning(segmentID: "tool-plan", text: text)]
        case .messageEnd(_, let usage):
            var actions: [Action] = []
            if let tokens = usage?.tokens {
                actions.append(.usage(
                    inputTokens: tokens.inputTokens ?? 0,
                    cachedTokens: usage?.cachedTokens ?? 0,
                    outputTokens: tokens.outputTokens ?? 0,
                    reasoningTokens: tokens.reasoningTokens ?? 0
                ))
            }
            actions.append(.finished)
            return actions
        case .contentEnd, .toolCallStart, .toolCallDelta, .toolCallEnd,
            .citationStart, .citationEnd, .unknown:
            return []
        }
    }

    /// Stable per-content-block segment IDs so #18 can attach citation
    /// metadata (and replace segments) addressably.
    private func segmentID(_ index: Int) -> String {
        "cohere-content-\(index)"
    }
}
#endif
