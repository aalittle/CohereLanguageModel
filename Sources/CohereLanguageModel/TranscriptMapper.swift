#if compiler(>=6.4)
import Foundation
import FoundationModels
import CohereAPI

/// Translates Apple transcripts into Cohere Chat V2 messages (FR-3).
///
/// Pure functions, no I/O. All six entry types map without loss:
///
/// | Apple entry | Cohere message |
/// |---|---|
/// | `instructions` | `system` |
/// | `prompt` | `user` |
/// | `response` | `assistant` (text content) |
/// | `toolCalls` | `assistant` with `tool_calls` (arguments as JSON) |
/// | `toolOutput` | `tool`, linked via `tool_call_id` |
/// | `reasoning` | `assistant` with a `thinking` content block |
///
/// The `reasoning` mapping mirrors how Command A+ itself emits reasoning
/// (`thinking` content blocks — observed in the #4 fixtures, not just
/// tool-plan text). Verified against the live API in #13.
///
/// Throws ``TranscriptMappingError`` for content Cohere cannot represent
/// (attachment and custom segments — out of scope). The
/// executor maps that onto `LanguageModelError.unsupportedTranscriptContent`,
/// which is 27-only and therefore not thrown directly from here.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, watchOS 27.0, *)
enum TranscriptMapper {
    static func messages(from transcript: Transcript) throws -> [ChatMessage] {
        try transcript.map(message(from:))
    }

    static func message(from entry: Transcript.Entry) throws -> ChatMessage {
        switch entry {
        case .instructions(let instructions):
            return .system(try text(of: instructions.segments, in: entry))
        case .prompt(let prompt):
            return .user(try text(of: prompt.segments, in: entry))
        case .response(let response):
            return .assistant(.init(
                content: try contentBlocks(of: response.segments, in: entry)
            ))
        case .toolCalls(let calls):
            return .assistant(.init(toolCalls: calls.map { call in
                ToolCall(
                    id: call.id,
                    function: .init(
                        name: call.toolName,
                        arguments: call.arguments.jsonString
                    )
                )
            }))
        case .toolOutput(let output):
            // ToolOutput.id is the originating call's ID — the same value
            // apps receive in Transcript.ToolCall.id — which is exactly
            // Cohere's tool_call_id linkage.
            return .tool(
                toolCallID: output.id,
                content: try text(of: output.segments, in: entry)
            )
        default:
            if #available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *),
                case .reasoning(let reasoning) = entry
            {
                return .assistant(.init(
                    content: [.thinking(try text(of: reasoning.segments, in: entry))]
                ))
            }
            throw TranscriptMappingError.unsupportedEntry(id: entry.id)
        }
    }

    /// Concatenated text of segments, in order. Structured segments
    /// contribute their JSON representation — structured content survives
    /// the trip rather than being dropped.
    private static func text(
        of segments: [Transcript.Segment], in entry: Transcript.Entry
    ) throws -> String {
        try segments.map { try text(of: $0, in: entry) }.joined(separator: "\n")
    }

    private static func contentBlocks(
        of segments: [Transcript.Segment], in entry: Transcript.Entry
    ) throws -> [ContentBlock] {
        try segments.map { .text(try text(of: $0, in: entry)) }
    }

    private static func text(
        of segment: Transcript.Segment, in entry: Transcript.Entry
    ) throws -> String {
        switch segment {
        case .text(let segment):
            return segment.content
        case .structure(let segment):
            return segment.content.jsonString
        default:
            // Attachment and custom segments (both 27-only) have no Chat V2
            // representation; dropping them silently would be lossy (FR-3).
            throw TranscriptMappingError.unsupportedSegment(
                entryID: entry.id, segmentID: segment.id
            )
        }
    }
}

/// Transcript content that cannot be represented in a Chat V2 request.
/// Wrapped into `LanguageModelError.unsupportedTranscriptContent` by the
/// executor (#10); kept separate because that error is 27-only while the
/// mapper runs wherever transcripts exist (macOS 26+).
@available(iOS 26.0, macOS 26.0, visionOS 26.0, watchOS 27.0, *)
enum TranscriptMappingError: Error, Equatable {
    case unsupportedEntry(id: String)
    case unsupportedSegment(entryID: String, segmentID: String)
}
#endif
