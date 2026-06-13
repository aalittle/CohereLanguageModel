import Foundation

/// A Cohere Chat V2 request body (`POST /v2/chat`).
///
/// Generation parameters are optional and omitted from the encoded JSON when
/// `nil`, so the server applies its own defaults — the executor only sends
/// what the developer explicitly set (FR-5).
public struct ChatRequest: Sendable, Equatable, Codable {
    /// Model ID, e.g. `command-a-plus-05-2026`. Always configuration, never
    /// hardcoded by callers, so the package survives model deprecations.
    public var model: String
    /// Conversation history, in order. Include all prior turns and the new
    /// user prompt; the API is stateless.
    public var messages: [ChatMessage]
    /// When `true`, the response arrives as an SSE event stream.
    public var stream: Bool?
    /// Tools the model may call (FR-9).
    public var tools: [ToolDefinition]?
    /// Grounding documents; their presence triggers citation events (FR-13 prep).
    public var documents: [Document]?
    /// Constrain response shape; use ``ResponseFormat/jsonObject`` for
    /// structured output (FR-11 prep).
    public var responseFormat: ResponseFormat?
    /// Sampling temperature in [0, 1]. Higher values are more random.
    /// `nil` uses the server default.
    public var temperature: Double?
    /// Maximum output tokens. `nil` uses the server default.
    ///
    /// > Note: Command A+ emits reasoning (thinking blocks) before answering.
    /// > Set this generously — a budget consumed entirely by reasoning produces
    /// > no visible text.
    public var maxTokens: Int?
    /// Nucleus (top-p) sampling.
    public var p: Double?
    /// Top-k sampling.
    public var k: Int?
    /// Fixed random seed for reproducible outputs.
    public var seed: Int?
    /// Stop generation when any of these sequences is produced.
    public var stopSequences: [String]?

    public init(
        model: String,
        messages: [ChatMessage],
        stream: Bool? = nil,
        tools: [ToolDefinition]? = nil,
        documents: [Document]? = nil,
        responseFormat: ResponseFormat? = nil,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        p: Double? = nil,
        k: Int? = nil,
        seed: Int? = nil,
        stopSequences: [String]? = nil
    ) {
        self.model = model
        self.messages = messages
        self.stream = stream
        self.tools = tools
        self.documents = documents
        self.responseFormat = responseFormat
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.p = p
        self.k = k
        self.seed = seed
        self.stopSequences = stopSequences
    }

    private enum CodingKeys: String, CodingKey {
        case model, messages, stream, tools, documents
        case responseFormat = "response_format"
        case temperature
        case maxTokens = "max_tokens"
        case p, k, seed
        case stopSequences = "stop_sequences"
    }
}

/// One turn in a Chat V2 conversation, discriminated by `role`.
public enum ChatMessage: Sendable, Equatable {
    /// Instructions that shape all subsequent responses (the system prompt).
    case system(String)
    /// A human turn.
    case user(String)
    /// A prior model response, replayed for multi-turn context.
    case assistant(AssistantTurn)
    /// A tool result, linked to the originating call via `toolCallID`.
    case tool(toolCallID: String, content: String)

    /// An assistant turn replayed back to the API (e.g. from a transcript).
    public struct AssistantTurn: Sendable, Equatable, Codable {
        public var content: [ContentBlock]?
        public var toolPlan: String?
        public var toolCalls: [ToolCall]?

        public init(
            content: [ContentBlock]? = nil,
            toolPlan: String? = nil,
            toolCalls: [ToolCall]? = nil
        ) {
            self.content = content
            self.toolPlan = toolPlan
            self.toolCalls = toolCalls
        }

        private enum CodingKeys: String, CodingKey {
            case content
            case toolPlan = "tool_plan"
            case toolCalls = "tool_calls"
        }
    }

    /// Convenience for a plain-text assistant turn.
    public static func assistant(text: String) -> ChatMessage {
        .assistant(AssistantTurn(content: [.text(text)]))
    }
}

extension ChatMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case role, content
        case toolPlan = "tool_plan"
        case toolCalls = "tool_calls"
        case toolCallID = "tool_call_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let role = try container.decode(String.self, forKey: .role)
        switch role {
        case "system":
            self = .system(try container.decode(String.self, forKey: .content))
        case "user":
            self = .user(try container.decode(String.self, forKey: .content))
        case "assistant":
            self = .assistant(try ChatMessage.AssistantTurn(from: decoder))
        case "tool":
            self = .tool(
                toolCallID: try container.decode(String.self, forKey: .toolCallID),
                content: try container.decode(String.self, forKey: .content)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .role, in: container,
                debugDescription: "Unknown message role '\(role)'"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .system(let content):
            try container.encode("system", forKey: .role)
            try container.encode(content, forKey: .content)
        case .user(let content):
            try container.encode("user", forKey: .role)
            try container.encode(content, forKey: .content)
        case .assistant(let turn):
            try container.encode("assistant", forKey: .role)
            try container.encodeIfPresent(turn.content, forKey: .content)
            try container.encodeIfPresent(turn.toolPlan, forKey: .toolPlan)
            try container.encodeIfPresent(turn.toolCalls, forKey: .toolCalls)
        case .tool(let toolCallID, let content):
            try container.encode("tool", forKey: .role)
            try container.encode(toolCallID, forKey: .toolCallID)
            try container.encode(content, forKey: .content)
        }
    }
}

/// A tool the model may call, defined by a JSON Schema (FR-9 prep).
public struct ToolDefinition: Sendable, Equatable, Codable {
    /// Always `"function"` — the only tool type Cohere Chat V2 defines.
    public let type: String
    public var function: Function

    public struct Function: Sendable, Equatable, Codable {
        public var name: String
        public var description: String?
        /// JSON Schema for the arguments object.
        public var parameters: JSONValue

        public init(name: String, description: String? = nil, parameters: JSONValue) {
            self.name = name
            self.description = description
            self.parameters = parameters
        }
    }

    public init(function: Function) {
        self.type = "function"
        self.function = function
    }
}

/// A grounding document passed with a request. Citation sources echo these
/// back with the same `id`.
public struct Document: Sendable, Equatable, Codable {
    public var id: String?
    /// Open-ended document payload; by convention `title` and `text`.
    public var data: [String: JSONValue]

    public init(id: String? = nil, data: [String: JSONValue]) {
        self.id = id
        self.data = data
    }
}

/// Requested output shape (FR-11 prep).
public struct ResponseFormat: Sendable, Equatable, Codable {
    public var type: String
    public var jsonSchema: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case type
        case jsonSchema = "json_schema"
    }

    public static let text = ResponseFormat(type: "text")
    public static let jsonObject = ResponseFormat(type: "json_object")
    public static func jsonSchema(_ schema: JSONValue) -> ResponseFormat {
        ResponseFormat(type: "json_object", jsonSchema: schema)
    }

    init(type: String, jsonSchema: JSONValue? = nil) {
        self.type = type
        self.jsonSchema = jsonSchema
    }
}
