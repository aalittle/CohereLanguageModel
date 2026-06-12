import Foundation
import Testing
@testable import CohereAPI

/// Smoke tests proving the recorded fixtures (issue #4) are bundled and
/// loadable. Real parsing tests arrive with issues #6 and #7.
@Suite struct FixtureTests {
    static let fixtureNames = [
        "chat-basic.json",
        "chat-stream-basic.sse",
        "chat-stream-citations.sse",
        "chat-stream-tools.sse",
    ]

    @Test(arguments: fixtureNames)
    func fixtureIsBundledAndNonEmpty(name: String) throws {
        let url = try #require(Bundle.module.url(
            forResource: (name as NSString).deletingPathExtension,
            withExtension: (name as NSString).pathExtension,
            subdirectory: "Fixtures"
        ), "missing fixture \(name)")
        let data = try Data(contentsOf: url)
        #expect(!data.isEmpty)
    }

    @Test func citationFixtureContainsCitationEvents() throws {
        let url = try #require(Bundle.module.url(
            forResource: "chat-stream-citations", withExtension: "sse", subdirectory: "Fixtures"
        ))
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains(#""type":"citation-start""#))
        #expect(text.contains(#""type":"citation-end""#))
    }
}
