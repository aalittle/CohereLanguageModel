// StreamTranslator is framework-free, so these run at runtime on any host
// with the beta toolchain — they exercise the real translation policy
// against the recorded fixtures, end to end through the SSE parser.
#if compiler(>=6.4)
import Foundation
import Testing
@testable import CohereAPI
@testable import CohereLanguageModel

func translateFixture(_ name: String) throws -> [StreamTranslator.Action] {
    // Fixtures are bundled with CohereAPITests; reach them by path to
    // avoid duplicating recorded captures across test targets.
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // CohereLanguageModelTests/
        .deletingLastPathComponent()  // Tests/
        .appendingPathComponent("CohereAPITests/Fixtures/\(name).sse")
    var parser = ChatStreamParser()
    var translator = StreamTranslator()
    var actions: [StreamTranslator.Action] = []
    for event in parser.feed(try Data(contentsOf: url)) + parser.finish() {
        actions += translator.translate(event)
    }
    return actions
}

@Suite struct StreamTranslatorTests {
    @Test func metadataPrecedesAllTextActions() throws {
        let actions = try translateFixture("chat-stream-basic")
        guard case .metadata(let requestID) = try #require(actions.first) else {
            Issue.record("first action must be metadata"); return
        }
        #expect(!requestID.isEmpty)
    }

    @Test func basicStreamEndsWithUsageThenFinished() throws {
        let actions = try translateFixture("chat-stream-basic")
        #expect(actions.last == .finished)
        guard case .usage(let input, let cached, let output, let reasoning) =
            try #require(actions.dropLast().last)
        else { Issue.record("usage must precede finished"); return }
        #expect(input == 38)
        #expect(cached == 0)
        #expect(output == 73)
        #expect(reasoning == 61)
    }

    @Test func textReassemblesOnStableSegmentID() throws {
        let actions = try translateFixture("chat-stream-basic")
        var bySegment: [String: String] = [:]
        for case .appendText(let segmentID, let text) in actions {
            bySegment[segmentID, default: ""] += text
        }
        #expect(bySegment.count == 1)
        #expect(try #require(bySegment.values.first).contains("1 2 3 4 5"))
    }

    @Test func thinkingBlocksRouteToReasoningNotText() throws {
        let actions = try translateFixture("chat-stream-citations")
        let reasoningSegments = Set(actions.compactMap {
            if case .appendReasoning(let id, _) = $0 { id } else { nil }
        })
        let textSegments = Set(actions.compactMap {
            if case .appendText(let id, _) = $0 { id } else { nil }
        })
        // The citation stream has a thinking block (index 0) and a text
        // block (index 1) — they must land in different action kinds with
        // disjoint segment IDs.
        #expect(reasoningSegments == ["cohere-content-0"])
        #expect(textSegments == ["cohere-content-1"])
    }

    @Test func citationAndToolEventsProduceNoActionsInV1() throws {
        let actions = try translateFixture("chat-stream-tools")
        // Tool-call fragments must not leak into text or reasoning.
        for case .appendText(_, let text) in actions {
            #expect(!text.contains("equipment_id"))
        }
        // Stream still completes normally.
        #expect(actions.last == .finished)
    }

    @Test func toolPlanDeltaRoutesToReasoning() {
        var translator = StreamTranslator()
        let actions = translator.translate(.toolPlanDelta(text: "Check status first."))
        #expect(actions == [.appendReasoning(segmentID: "tool-plan", text: "Check status first.")])
    }

    @Test func messageEndWithoutUsageStillFinishes() {
        var translator = StreamTranslator()
        let actions = translator.translate(.messageEnd(finishReason: .complete, usage: nil))
        #expect(actions == [.finished])
    }
}
#endif
