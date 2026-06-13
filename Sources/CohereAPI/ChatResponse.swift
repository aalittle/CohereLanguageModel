import Foundation

/// A non-streamed Chat V2 response body.
public struct ChatResponse: Sendable, Equatable, Codable {
    public var id: String
    public var message: AssistantMessage
    public var finishReason: FinishReason
    public var usage: Usage?

    private enum CodingKeys: String, CodingKey {
        case id, message, usage
        case finishReason = "finish_reason"
    }
}

/// The assistant message in a response: ordered content blocks plus any
/// tool plan, tool calls, and citations.
public struct AssistantMessage: Sendable, Equatable, Codable {
    /// Always `"assistant"` on the wire.
    public var role: String
    /// Ordered content blocks (text, thinking, …).
    public var content: [ContentBlock]?
    /// Pre-call reasoning the model produced before selecting tools.
    public var toolPlan: String?
    /// Tool invocations requested by the model.
    public var toolCalls: [ToolCall]?
    /// Citations grounding text spans in source documents.
    public var citations: [Citation]?

    private enum CodingKeys: String, CodingKey {
        case role, content, citations
        case toolPlan = "tool_plan"
        case toolCalls = "tool_calls"
    }

    /// All text-block content joined, ignoring thinking blocks.
    public var text: String {
        (content ?? []).compactMap {
            if case .text(let text) = $0 { return text } else { return nil }
        }.joined()
    }
}

/// One typed block of assistant content. Command models stream reasoning as
/// `thinking` blocks interleaved with `text` blocks (observed in fixtures;
/// the documented event vocabulary only anticipated tool-plan reasoning).
///
/// Unrecognized block types decode as ``other(type:)`` rather than throwing,
/// per NFR-5 — new block kinds must not break existing apps.
public enum ContentBlock: Sendable, Equatable {
    case text(String)
    case thinking(String)
    case other(type: String)
}

extension ContentBlock: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, text, thinking
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        case "thinking":
            self = .thinking(try container.decode(String.self, forKey: .thinking))
        default:
            self = .other(type: type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .thinking(let thinking):
            try container.encode("thinking", forKey: .type)
            try container.encode(thinking, forKey: .thinking)
        case .other(let type):
            try container.encode(type, forKey: .type)
        }
    }
}

/// A tool invocation produced by the model. `arguments` is a raw JSON string,
/// as delivered on the wire (it accumulates incrementally when streaming).
public struct ToolCall: Sendable, Equatable, Codable {
    public var id: String
    /// Always `"function"` — the only tool type Cohere Chat V2 defines.
    public let type: String
    public var function: Function

    public struct Function: Sendable, Equatable, Codable {
        public var name: String
        public var arguments: String

        public init(name: String, arguments: String) {
            self.name = name
            self.arguments = arguments
        }
    }

    public init(id: String, function: Function) {
        self.id = id
        self.type = "function"
        self.function = function
    }
}

/// A citation grounding a span of response text in source documents.
/// Offsets are character positions into the complete text of the content
/// block at `contentIndex`.
public struct Citation: Sendable, Equatable, Codable {
    /// Start character offset (inclusive) in the content block text.
    public var start: Int
    /// End character offset (exclusive) in the content block text.
    public var end: Int
    /// The exact response text span being cited.
    public var text: String
    /// Source documents that back this citation.
    public var sources: [Source]
    /// Citation type string from the API, e.g. `"document"` or `"tool"`.
    public var type: String?
    /// Index of the content block whose offsets `start`/`end` address.
    public var contentIndex: Int?

    private enum CodingKeys: String, CodingKey {
        case start, end, text, sources, type
        case contentIndex = "content_index"
    }

    public struct Source: Sendable, Equatable, Codable {
        public var type: String
        public var id: String?
        /// The source document, echoed flat (`id`, `title`, `text`, ...).
        public var document: [String: JSONValue]?
    }
}

/// Token accounting from `message-end` / non-streamed responses.
/// `tokens` is actual consumption (what maps to Apple's usage events);
/// `billedUnits` is Cohere's billing view — related but distinct.
public struct Usage: Sendable, Equatable, Codable {
    public var billedUnits: BilledUnits?
    public var tokens: Tokens?
    public var cachedTokens: Int?

    private enum CodingKeys: String, CodingKey {
        case billedUnits = "billed_units"
        case tokens
        case cachedTokens = "cached_tokens"
    }

    public struct BilledUnits: Sendable, Equatable, Codable {
        public var inputTokens: Int?
        public var outputTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }

    public struct Tokens: Sendable, Equatable, Codable {
        public var inputTokens: Int?
        public var outputTokens: Int?
        public var reasoningTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case reasoningTokens = "reasoning_tokens"
        }
    }
}

/// Why generation stopped. Modeled as `RawRepresentable` rather than an enum
/// so unknown future values decode without throwing (NFR-5).
public struct FinishReason: RawRepresentable, Sendable, Hashable, Codable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let complete = FinishReason(rawValue: "COMPLETE")
    public static let maxTokens = FinishReason(rawValue: "MAX_TOKENS")
    public static let stopSequence = FinishReason(rawValue: "STOP_SEQUENCE")
    public static let toolCall = FinishReason(rawValue: "TOOL_CALL")
    public static let error = FinishReason(rawValue: "ERROR")
}

/// A Chat V2 error body (e.g. the 429 quota message).
public struct APIErrorBody: Sendable, Equatable, Codable {
    public var id: String?
    public var message: String
}
