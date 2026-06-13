import Foundation
import Testing
@testable import CohereAPI

/// Opt-in tests that hit the real Cohere API. Disabled by default — no
/// network in CI (NFR-6). Enable with:
///
/// ```sh
/// COHERE_LIVE_TESTS=1 \
///   COHERE_API_KEY=$(security find-generic-password -s cohere-prod-api-key -w) \
///   swift test --filter LiveTests
/// ```
///
/// These validate the live wire format against the recorded fixtures —
/// the early-warning that Cohere's Chat V2 schema has drifted. Keep them
/// minimal: the production key is metered.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["COHERE_LIVE_TESTS"] == "1"))
struct LiveTests {
    func apiKey() throws -> String {
        try #require(
            ProcessInfo.processInfo.environment["COHERE_API_KEY"],
            "Set COHERE_API_KEY for live tests"
        )
    }

    @Test func streamedChatProducesParseableEvents() async throws {
        let transport = URLSessionChatTransport(authorization: { try self.apiKey() })
        // maxTokens is generous: Command A+ reasons (thinking blocks)
        // before answering, and a tight budget can be spent entirely on
        // reasoning with no text emitted — observed live, not hypothetical.
        let request = ChatRequest(
            model: "command-a-plus-05-2026",
            messages: [.user("Reply with exactly: live ok")],
            stream: true,
            temperature: 0,
            maxTokens: 256
        )

        var parser = ChatStreamParser()
        var events: [ChatStreamEvent] = []
        for try await chunk in try await transport.stream(
            request, baseURL: CohereAPI.defaultBaseURL
        ) {
            events += parser.feed(chunk)
        }
        events += parser.finish()

        // Same shape the fixtures encode: a request ID, reassembled
        // content (text and/or thinking), and a terminal usage report.
        guard case .messageStart(let id) = try #require(events.first) else {
            Issue.record("first live event must be message-start"); return
        }
        #expect(id?.isEmpty == false)

        let content = events.reduce(into: "") {
            switch $1 {
            case .contentDelta(_, .text(let fragment)),
                .contentDelta(_, .thinking(let fragment)):
                $0 += fragment
            default:
                break
            }
        }
        #expect(!content.isEmpty)

        guard case .messageEnd(_, let usage) = try #require(events.last) else {
            Issue.record("last live event must be message-end"); return
        }
        #expect((usage?.tokens?.outputTokens ?? 0) > 0)
    }
}
