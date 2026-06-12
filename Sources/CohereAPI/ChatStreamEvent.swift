import Foundation

/// One typed event from a Chat V2 SSE stream.
///
/// `index` values identify the content block / tool call / citation a delta
/// belongs to; blocks with distinct indices interleave (e.g. a `thinking`
/// block at index 0 streams before the `text` block at index 1).
///
/// Unknown event types decode as ``unknown(type:)`` rather than throwing —
/// new server event kinds must never break existing clients (NFR-5).
public enum ChatStreamEvent: Sendable, Equatable {
    case messageStart(id: String?)
    case contentStart(index: Int, block: ContentBlock?)
    case contentDelta(index: Int, delta: ContentDelta)
    case contentEnd(index: Int)
    /// Reasoning about tool use. Not observed from Command A+ (which emits
    /// `thinking` content blocks instead) but part of the documented
    /// vocabulary for other Command models.
    case toolPlanDelta(text: String)
    case toolCallStart(index: Int, call: ToolCall)
    case toolCallDelta(index: Int, argumentsFragment: String)
    case toolCallEnd(index: Int)
    case citationStart(index: Int, citation: Citation)
    case citationEnd(index: Int)
    case messageEnd(finishReason: FinishReason?, usage: Usage?)
    case unknown(type: String)

    /// One streamed increment of a content block.
    public enum ContentDelta: Sendable, Equatable {
        case text(String)
        case thinking(String)
    }
}

/// Decodes a single SSE `data:` payload into a ``ChatStreamEvent``.
public enum ChatStreamEventDecoder {
    /// - Throws: `DecodingError` when the payload is not valid JSON or a
    ///   known event type arrives without its required fields. Callers
    ///   following NFR-5 skip-and-log rather than failing the stream.
    public static func decode(_ payload: Data) throws -> ChatStreamEvent {
        let raw = try JSONDecoder().decode(RawEvent.self, from: payload)
        let message = raw.delta?.message

        func index() throws -> Int {
            guard let index = raw.index else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: [],
                    debugDescription: "\(raw.type) event missing index"
                ))
            }
            return index
        }

        switch raw.type {
        case "message-start":
            return .messageStart(id: raw.id)
        case "content-start":
            return .contentStart(index: try index(), block: message?.contentBlock)
        case "content-delta":
            guard let delta = message?.contentDelta else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: [],
                    debugDescription: "content-delta without text or thinking"
                ))
            }
            return .contentDelta(index: try index(), delta: delta)
        case "content-end":
            return .contentEnd(index: try index())
        case "tool-plan-delta":
            return .toolPlanDelta(text: message?.toolPlanText ?? "")
        case "tool-call-start":
            guard let call = message?.toolCallStart else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: [],
                    debugDescription: "tool-call-start without tool call"
                ))
            }
            return .toolCallStart(index: try index(), call: call)
        case "tool-call-delta":
            return .toolCallDelta(
                index: try index(),
                argumentsFragment: message?.toolCallArgumentsFragment ?? ""
            )
        case "tool-call-end":
            return .toolCallEnd(index: try index())
        case "citation-start":
            guard let citation = message?.citation else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: [],
                    debugDescription: "citation-start without citation"
                ))
            }
            return .citationStart(index: try index(), citation: citation)
        case "citation-end":
            return .citationEnd(index: try index())
        case "message-end":
            return .messageEnd(
                finishReason: raw.delta?.finishReason,
                usage: raw.delta?.usage
            )
        default:
            return .unknown(type: raw.type)
        }
    }
}

// MARK: - Raw wire envelope

/// The lenient envelope shared by all stream events. Fields that hold
/// different JSON shapes per event type (`content`, `tool_calls`,
/// `citations` — single objects in deltas, empty arrays in message-start)
/// decode through tolerant wrappers that yield `nil` instead of throwing.
private struct RawEvent: Decodable {
    var type: String
    var id: String?
    var index: Int?
    var delta: Delta?

    struct Delta: Decodable {
        var message: Message?
        var finishReason: FinishReason?
        var usage: Usage?

        enum CodingKeys: String, CodingKey {
            case message, usage
            case finishReason = "finish_reason"
        }
    }

    struct Message: Decodable {
        var content: Lenient<ContentPayload>?
        var toolPlan: Lenient<String>?
        var toolCalls: Lenient<StreamToolCall>?
        var citations: Lenient<Citation>?

        enum CodingKeys: String, CodingKey {
            case content, citations
            case toolPlan = "tool_plan"
            case toolCalls = "tool_calls"
        }

        var contentBlock: ContentBlock? {
            guard let payload = content?.value else { return nil }
            if let type = payload.type {
                switch type {
                case "text": return .text(payload.text ?? "")
                case "thinking": return .thinking(payload.thinking ?? "")
                default: return .other(type: type)
                }
            }
            return nil
        }

        var contentDelta: ChatStreamEvent.ContentDelta? {
            guard let payload = content?.value else { return nil }
            if let text = payload.text { return .text(text) }
            if let thinking = payload.thinking { return .thinking(thinking) }
            return nil
        }

        var toolPlanText: String? { toolPlan?.value }

        var toolCallStart: ToolCall? {
            guard let call = toolCalls?.value, let id = call.id,
                let function = call.function, let name = function.name
            else { return nil }
            return ToolCall(
                id: id,
                function: .init(name: name, arguments: function.arguments ?? "")
            )
        }

        var toolCallArgumentsFragment: String? {
            toolCalls?.value?.function?.arguments
        }

        var citation: Citation? { citations?.value }
    }

    /// A content payload in either content-start form ({type, text|thinking})
    /// or content-delta form ({text} / {thinking}).
    struct ContentPayload: Decodable {
        var type: String?
        var text: String?
        var thinking: String?
    }

    /// A partial tool call as it appears in tool-call-start (full) and
    /// tool-call-delta (arguments fragment only) events.
    struct StreamToolCall: Decodable {
        var id: String?
        var function: Function?

        struct Function: Decodable {
            var name: String?
            var arguments: String?
        }
    }
}

/// Decodes the wrapped value, or `nil` when the JSON holds a different
/// shape (e.g. message-start's empty arrays where deltas carry objects).
private struct Lenient<Wrapped: Decodable>: Decodable {
    var value: Wrapped?

    init(from decoder: Decoder) throws {
        value = try? decoder.singleValueContainer().decode(Wrapped.self)
    }
}
