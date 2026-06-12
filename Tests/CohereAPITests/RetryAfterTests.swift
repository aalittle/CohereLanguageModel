import Foundation
import Testing
@testable import CohereAPI

@Suite struct RetryAfterTests {
    @Test func deltaSecondsParse() throws {
        let date = try #require(URLSessionChatTransport.retryAfterDate(from: "30"))
        #expect(abs(date.timeIntervalSinceNow - 30) < 2)
    }

    @Test func httpDateParses() throws {
        let date = try #require(URLSessionChatTransport.retryAfterDate(
            from: "Fri, 12 Jun 2026 22:00:00 GMT"
        ))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "GMT"))
        let parts = calendar.dateComponents([.year, .hour], from: date)
        #expect(parts.year == 2026)
        #expect(parts.hour == 22)
    }

    @Test func garbageReturnsNil() {
        #expect(URLSessionChatTransport.retryAfterDate(from: "soonish") == nil)
    }
}
