import Foundation
import Testing
@testable import CohereAPI

func fixture(_ name: String, _ ext: String) throws -> Data {
    let url = try #require(Bundle.module.url(
        forResource: name, withExtension: ext, subdirectory: "Fixtures"
    ))
    return try Data(contentsOf: url)
}

func parseAll(_ data: Data, chunkSize: Int? = nil) -> [ChatStreamEvent] {
    var parser = ChatStreamParser()
    var events: [ChatStreamEvent] = []
    if let chunkSize {
        var rest = data[...]
        while !rest.isEmpty {
            events += parser.feed(Data(rest.prefix(chunkSize)))
            rest = rest.dropFirst(chunkSize)
        }
    } else {
        events = parser.feed(data)
    }
    return events + parser.finish()
}

@Suite struct StreamFixtureTests {
    @Test func parsesBasicStreamEndToEnd() throws {
        let events = parseAll(try fixture("chat-stream-basic", "sse"))

        guard case .messageStart(let id) = try #require(events.first) else {
            Issue.record("first event must be message-start"); return
        }
        #expect(id?.isEmpty == false)

        guard case .messageEnd(let reason, let usage) = try #require(events.last) else {
            Issue.record("last event must be message-end"); return
        }
        #expect(reason == .complete)
        #expect(usage?.tokens?.inputTokens == 38)
        #expect(usage?.tokens?.reasoningTokens == 61)

        // The streamed text deltas reassemble into the full answer.
        let text = events.reduce(into: "") {
            if case .contentDelta(_, .text(let fragment)) = $1 { $0 += fragment }
        }
        #expect(text.contains("1 2 3 4 5"))
        #expect(events.contains { if case .unknown = $0 { true } else { false } } == false)
    }

    @Test func parsesCitationStreamWithOffsets() throws {
        let events = parseAll(try fixture("chat-stream-citations", "sse"))

        let citations = events.compactMap {
            if case .citationStart(_, let citation) = $0 { citation } else { nil }
        }
        #expect(citations.count == 9)
        let first = try #require(citations.first)
        #expect(first.start == 13)
        #expect(first.end == 38)
        #expect(first.text == "Pump P-301 Service Manual")
        #expect(first.sources.first?.id == "doc-pump-manual")
        #expect(first.contentIndex == 1)

        // Thinking and text blocks stream at distinct indices.
        let starts = events.compactMap {
            if case .contentStart(let index, let block) = $0 { (index, block) } else { nil }
        }
        #expect(starts.count == 2)
        #expect(starts.first?.1 == .thinking(""))
        #expect(starts.last?.1 == .text(""))
    }

    @Test func parsesToolCallStreamAndReassemblesArguments() throws {
        let events = parseAll(try fixture("chat-stream-tools", "sse"))

        guard case .toolCallStart(let index, let call) = try #require(
            events.first(where: { if case .toolCallStart = $0 { true } else { false } })
        ) else { return }
        #expect(index == 0)
        #expect(call.function.name == "get_equipment_status")

        let arguments = events.reduce(into: call.function.arguments) {
            if case .toolCallDelta(_, let fragment) = $1 { $0 += fragment }
        }
        let parsed = try JSONDecoder().decode(JSONValue.self, from: Data(arguments.utf8))
        #expect(parsed == ["equipment_id": "P-301"])
        #expect(events.contains { if case .toolCallEnd = $0 { true } else { false } })
    }

    @Test(arguments: [1, 7, 64, 1024])
    func chunkBoundariesDoNotChangeEvents(chunkSize: Int) throws {
        let data = try fixture("chat-stream-citations", "sse")
        #expect(parseAll(data, chunkSize: chunkSize) == parseAll(data))
    }
}

@Suite struct StreamRobustnessTests {
    @Test func malformedJSONIsSkippedAndStreamContinues() {
        var parser = ChatStreamParser()
        let stream = """
        data: {"type":"message-start","id":"abc"}\n
        data: {not json at all\n
        data: {"type":"content-end","index":0}\n
        """
        let events = parser.feed(Data(stream.utf8)) + parser.finish()
        #expect(events == [.messageStart(id: "abc"), .contentEnd(index: 0)])
    }

    @Test func unknownEventTypeSurfacesAsUnknown() {
        var parser = ChatStreamParser()
        let events = parser.feed(Data("data: {\"type\":\"telepathy-delta\"}\n\n".utf8))
        #expect(events == [.unknown(type: "telepathy-delta")])
    }

    @Test func knownEventMissingRequiredFieldsIsSkipped() {
        var parser = ChatStreamParser()
        // content-delta without index or content must not crash or emit.
        let events = parser.feed(Data("data: {\"type\":\"content-delta\"}\n\n".utf8))
        #expect(events.isEmpty)
    }

    @Test func toolCallStartWithoutCallIsSkipped() {
        var parser = ChatStreamParser()
        let events = parser.feed(Data("data: {\"type\":\"tool-call-start\",\"index\":0}\n\n".utf8))
        #expect(events.isEmpty)
    }

    @Test func citationStartWithoutCitationIsSkipped() {
        var parser = ChatStreamParser()
        let events = parser.feed(Data("data: {\"type\":\"citation-start\",\"index\":0}\n\n".utf8))
        #expect(events.isEmpty)
    }

    @Test func indexedEventMissingIndexIsSkipped() {
        var parser = ChatStreamParser()
        // content-end requires an index; without it the decoder throws and
        // the parser skips it rather than crashing (NFR-5).
        let events = parser.feed(Data("data: {\"type\":\"content-end\"}\n\n".utf8))
        #expect(events.isEmpty)
    }

    @Test func toolPlanDeltaDecodes() throws {
        // Synthetic: not emitted by Command A+ (which uses thinking blocks)
        // but part of the documented vocabulary.
        let json = #"{"type":"tool-plan-delta","delta":{"message":{"tool_plan":"I will check."}}}"#
        let event = try ChatStreamEventDecoder.decode(Data(json.utf8))
        #expect(event == .toolPlanDelta(text: "I will check."))
    }

    @Test func crlfLineEndingsParse() {
        var parser = ChatStreamParser()
        let events = parser.feed(Data("data: {\"type\":\"content-end\",\"index\":2}\r\n\r\n".utf8))
        #expect(events == [.contentEnd(index: 2)])
    }

    @Test func multiLineDataFieldJoinsWithNewline() {
        var parser = SSEParser()
        let payloads = parser.feed(Data("data: line1\ndata: line2\n\n".utf8))
        #expect(payloads == ["line1\nline2"])
    }

    @Test func commentsAndUnusedFieldsAreIgnored() {
        var parser = SSEParser()
        let payloads = parser.feed(Data(": keepalive\nevent: message\nid: 7\ndata: x\n\n".utf8))
        #expect(payloads == ["x"])
    }

    @Test func finishFlushesUnterminatedEvent() {
        var parser = ChatStreamParser()
        #expect(parser.feed(Data("data: {\"type\":\"content-end\",\"index\":0}\n".utf8)).isEmpty)
        #expect(parser.finish() == [.contentEnd(index: 0)])
    }
}
