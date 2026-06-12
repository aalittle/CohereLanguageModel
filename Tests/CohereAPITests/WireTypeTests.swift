import Foundation
import Testing
@testable import CohereAPI

@Suite struct ResponseDecodingTests {
    func fixtureData(_ name: String, _ ext: String) throws -> Data {
        let url = try #require(Bundle.module.url(
            forResource: name, withExtension: ext, subdirectory: "Fixtures"
        ))
        return try Data(contentsOf: url)
    }

    @Test func decodesRealBasicChatResponse() throws {
        let response = try JSONDecoder().decode(
            ChatResponse.self, from: fixtureData("chat-basic", "json")
        )
        #expect(response.id == "ca26c680-6b40-4b26-a09b-2d0884c59caa")
        #expect(response.finishReason == .complete)
        #expect(response.message.role == "assistant")
        #expect(response.message.content?.count == 2)
        if case .thinking = try #require(response.message.content?.first) {} else {
            Issue.record("first block should be thinking")
        }
        #expect(response.message.text.hasPrefix("Retrieval-augmented generation"))
        #expect(response.usage?.tokens?.inputTokens == 38)
        #expect(response.usage?.tokens?.reasoningTokens == 29)
        #expect(response.usage?.billedUnits?.inputTokens == 13)
        #expect(response.usage?.cachedTokens == 0)
    }

    @Test func unknownContentBlockTypeDecodesAsOther() throws {
        let json = #"{"type":"hologram","payload":"future"}"#
        let block = try JSONDecoder().decode(ContentBlock.self, from: Data(json.utf8))
        #expect(block == .other(type: "hologram"))
    }

    @Test func unknownFinishReasonDecodesWithoutThrowing() throws {
        let json = #"{"id":"x","message":{"role":"assistant"},"finish_reason":"PAUSED_FOR_EFFECT"}"#
        let response = try JSONDecoder().decode(ChatResponse.self, from: Data(json.utf8))
        #expect(response.finishReason.rawValue == "PAUSED_FOR_EFFECT")
    }

    @Test func decodesRealToolCallShape() throws {
        // Inner payload of a tool-call-start event from chat-stream-tools.sse.
        let json = #"{"id":"get_equipment_status_xjaf0dk46d7h","type":"function","function":{"name":"get_equipment_status","arguments":""}}"#
        let call = try JSONDecoder().decode(ToolCall.self, from: Data(json.utf8))
        #expect(call.id == "get_equipment_status_xjaf0dk46d7h")
        #expect(call.function.name == "get_equipment_status")
    }

    @Test func decodesRealCitationShape() throws {
        // Inner citations payload of a citation-start event from chat-stream-citations.sse.
        let json = #"{"start":13,"end":38,"text":"Pump P-301 Service Manual","sources":[{"type":"document","id":"doc-pump-manual","document":{"id":"doc-pump-manual","text":"Pump P-301 requires bearing lubrication every 500 operating hours.","title":"Pump P-301 Service Manual"}}],"type":"TEXT_CONTENT","content_index":1}"#
        let citation = try JSONDecoder().decode(Citation.self, from: Data(json.utf8))
        #expect(citation.start == 13)
        #expect(citation.end == 38)
        #expect(citation.contentIndex == 1)
        #expect(citation.sources.first?.id == "doc-pump-manual")
        #expect(citation.sources.first?.document?["title"] == .string("Pump P-301 Service Manual"))
    }

    @Test func decodesRealErrorBody() throws {
        // Verbatim 429 body observed during #4 capture.
        let json = #"{"id":"24e32f6d-b372-4853-85f2-11e65134f032","message":"You are using a Trial key, which is limited to 1000 API calls / month."}"#
        let error = try JSONDecoder().decode(APIErrorBody.self, from: Data(json.utf8))
        #expect(error.message.contains("Trial key"))
    }
}

@Suite struct RequestEncodingTests {
    /// Mirrors the document-grounded request from scripts/capture-fixtures.sh.
    var groundedRequest: ChatRequest {
        ChatRequest(
            model: "command-a-plus-05-2026",
            messages: [.user("How often does P-301 need bearing lubrication?")],
            stream: true,
            documents: [
                Document(id: "doc-pump-manual", data: [
                    "title": "Pump P-301 Service Manual",
                    "text": "Pump P-301 requires bearing lubrication every 500 operating hours.",
                ])
            ]
        )
    }

    @Test func requestRoundTripsThroughJSON() throws {
        let request = ChatRequest(
            model: "command-a-plus-05-2026",
            messages: [
                .system("You are a field service assistant."),
                .user("Is pump P-301 running?"),
                .assistant(.init(
                    toolPlan: "I should check the equipment status.",
                    toolCalls: [ToolCall(
                        id: "call_1",
                        function: .init(name: "get_equipment_status", arguments: #"{"equipment_id":"P-301"}"#)
                    )]
                )),
                .tool(toolCallID: "call_1", content: #"{"status":"running"}"#),
                .assistant(text: "Yes, P-301 is currently running."),
            ],
            tools: [ToolDefinition(function: .init(
                name: "get_equipment_status",
                description: "Returns equipment status",
                parameters: [
                    "type": "object",
                    "properties": ["equipment_id": ["type": "string"]],
                    "required": ["equipment_id"],
                ]
            ))],
            temperature: 0.3,
            maxTokens: 512,
            seed: 42
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(ChatRequest.self, from: data)
        #expect(decoded == request)
    }

    @Test func encodedRequestUsesWireFieldNames() throws {
        let data = try JSONEncoder().encode(groundedRequest)
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object["model"] as? String == "command-a-plus-05-2026")
        #expect(object["stream"] as? Bool == true)
        let messages = try #require(object["messages"] as? [[String: Any]])
        #expect(messages.first?["role"] as? String == "user")
        let documents = try #require(object["documents"] as? [[String: Any]])
        #expect(documents.first?["id"] as? String == "doc-pump-manual")
    }

    @Test func nilGenerationParametersAreOmittedFromJSON() throws {
        let data = try JSONEncoder().encode(groundedRequest)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("temperature"))
        #expect(!json.contains("max_tokens"))
        #expect(!json.contains("response_format"))
        #expect(!json.contains("tools"))
    }

    @Test func toolMessageEncodesToolCallID() throws {
        let data = try JSONEncoder().encode(
            ChatMessage.tool(toolCallID: "call_9", content: "ok")
        )
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object["role"] as? String == "tool")
        #expect(object["tool_call_id"] as? String == "call_9")
    }

    @Test func jsonValueRoundTripsIntegersWithoutFloatification() throws {
        let schema: JSONValue = ["maxItems": 3, "ratio": 0.5]
        let data = try JSONEncoder().encode(schema)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains(#""maxItems":3"#))
        #expect(try JSONDecoder().decode(JSONValue.self, from: data) == schema)
    }
}
