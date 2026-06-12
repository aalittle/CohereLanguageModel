// Unlike ConfigurationTests, most of these execute at runtime on macOS 26
// hosts: five of the six entry types are 26-available — only `reasoning`
// (and attachment/custom segments) need a macOS 27 guard.
#if compiler(>=6.4)
import Foundation
import Testing
import FoundationModels
@testable import CohereAPI
@testable import CohereLanguageModel

@available(iOS 26.0, macOS 26.0, visionOS 26.0, watchOS 27.0, *)
func textSegments(_ texts: String...) -> [Transcript.Segment] {
    texts.map { .text(.init(content: $0)) }
}

@Suite struct TranscriptMapperTests {
    @Test func instructionsBecomeSystemMessage() throws {
        guard #available(macOS 26.0, iOS 26.0, *) else { return }
        let entry = Transcript.Entry.instructions(.init(
            segments: textSegments("You are a field service assistant."),
            toolDefinitions: []
        ))
        #expect(try TranscriptMapper.message(from: entry)
            == .system("You are a field service assistant."))
    }

    @Test func promptBecomesUserMessage() throws {
        guard #available(macOS 26.0, iOS 26.0, *) else { return }
        let entry = Transcript.Entry.prompt(.init(
            segments: textSegments("Is pump P-301 running?")
        ))
        #expect(try TranscriptMapper.message(from: entry)
            == .user("Is pump P-301 running?"))
    }

    @Test func multipleSegmentsJoinInOrder() throws {
        guard #available(macOS 26.0, iOS 26.0, *) else { return }
        let entry = Transcript.Entry.prompt(.init(
            segments: textSegments("First.", "Second.")
        ))
        #expect(try TranscriptMapper.message(from: entry) == .user("First.\nSecond."))
    }

    @Test func responseBecomesAssistantTextMessage() throws {
        guard #available(macOS 26.0, iOS 26.0, *) else { return }
        let entry = Transcript.Entry.response(.init(
            assetIDs: [],
            segments: textSegments("Yes, P-301 is running.")
        ))
        guard case .assistant(let turn) = try TranscriptMapper.message(from: entry) else {
            Issue.record("expected assistant message"); return
        }
        #expect(turn.content == [.text("Yes, P-301 is running.")])
        #expect(turn.toolCalls == nil)
    }

    @Test func toolCallsBecomeAssistantToolCallsWithJSONArguments() throws {
        guard #available(macOS 26.0, iOS 26.0, *) else { return }
        let arguments = try GeneratedContent(json: #"{"equipment_id":"P-301"}"#)
        let entry = Transcript.Entry.toolCalls(.init([
            Transcript.ToolCall(
                id: "call_1", toolName: "get_equipment_status", arguments: arguments
            )
        ]))
        guard case .assistant(let turn) = try TranscriptMapper.message(from: entry) else {
            Issue.record("expected assistant message"); return
        }
        let call = try #require(turn.toolCalls?.first)
        #expect(call.id == "call_1")
        #expect(call.function.name == "get_equipment_status")
        // jsonString formatting is the framework's; compare parsed values.
        let parsed = try JSONDecoder().decode(
            JSONValue.self, from: Data(call.function.arguments.utf8)
        )
        #expect(parsed == ["equipment_id": "P-301"])
    }

    @Test func toolOutputBecomesToolMessageLinkedByCallID() throws {
        guard #available(macOS 26.0, iOS 26.0, *) else { return }
        let entry = Transcript.Entry.toolOutput(.init(
            id: "call_1",
            toolName: "get_equipment_status",
            segments: textSegments(#"{"status":"running"}"#)
        ))
        #expect(try TranscriptMapper.message(from: entry)
            == .tool(toolCallID: "call_1", content: #"{"status":"running"}"#))
    }

    @Test func structuredSegmentsContributeJSONNotNothing() throws {
        guard #available(macOS 26.0, iOS 26.0, *) else { return }
        let entry = Transcript.Entry.prompt(.init(segments: [
            .text(.init(content: "Context:")),
            .structure(.init(
                id: "s1",
                source: "EquipmentReport",
                content: try GeneratedContent(json: #"{"pump":"P-301"}"#)
            )),
        ]))
        guard case .user(let content) = try TranscriptMapper.message(from: entry) else {
            Issue.record("expected user message"); return
        }
        #expect(content.hasPrefix("Context:\n"))
        #expect(content.contains("P-301"))
    }

    @Test func reasoningBecomesAssistantThinkingBlock() throws {
        guard #available(macOS 27.0, iOS 27.0, *) else { return }
        let entry = Transcript.Entry.reasoning(.init(
            segments: textSegments("The user needs the pump status first.")
        ))
        guard case .assistant(let turn) = try TranscriptMapper.message(from: entry) else {
            Issue.record("expected assistant message"); return
        }
        #expect(turn.content == [.thinking("The user needs the pump status first.")])
    }

    @Test func fullConversationMapsInOrderWithAllRoles() throws {
        guard #available(macOS 26.0, iOS 26.0, *) else { return }
        let arguments = try GeneratedContent(json: #"{"equipment_id":"P-301"}"#)
        let transcript = Transcript(entries: [
            .instructions(.init(segments: textSegments("Be terse."), toolDefinitions: [])),
            .prompt(.init(segments: textSegments("Is P-301 running?"))),
            .toolCalls(.init([
                .init(id: "call_1", toolName: "get_equipment_status", arguments: arguments)
            ])),
            .toolOutput(.init(
                id: "call_1", toolName: "get_equipment_status",
                segments: textSegments(#"{"status":"running"}"#)
            )),
            .response(.init(assetIDs: [], segments: textSegments("Yes."))),
        ])
        let messages = try TranscriptMapper.messages(from: transcript)
        #expect(messages.count == 5)
        #expect(messages[0] == .system("Be terse."))
        #expect(messages[1] == .user("Is P-301 running?"))
        if case .assistant(let turn) = messages[2] {
            #expect(turn.toolCalls?.first?.id == "call_1")
        } else { Issue.record("entry 2 should be assistant tool calls") }
        #expect(messages[3] == .tool(toolCallID: "call_1", content: #"{"status":"running"}"#))
        if case .assistant(let turn) = messages[4] {
            #expect(turn.content == [.text("Yes.")])
        } else { Issue.record("entry 4 should be assistant text") }
    }
}
#endif
