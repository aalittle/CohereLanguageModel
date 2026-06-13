import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CohereAPI

/// A `URLProtocol` that returns a canned HTTP response, so the transport's
/// status handling and byte streaming run deterministically with no network.
final class StubURLProtocol: URLProtocol {
    struct Stub: Sendable {
        var status: Int
        var headers: [String: String]
        var body: Data
    }

    // Set by each test before issuing a request; the suite is `.serialized`,
    // so only one test touches this at a time.
    nonisolated(unsafe) static var stub: Stub?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        if let stub = Self.stub, let url = request.url,
            let response = HTTPURLResponse(
                url: url, statusCode: stub.status,
                httpVersion: "HTTP/1.1", headerFields: stub.headers
            )
        {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stub.body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite(.serialized) struct URLSessionChatTransportTests {
    private let baseURL = URL(string: "https://api.cohere.test")!

    private func makeTransport() -> URLSessionChatTransport {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSessionChatTransport(session: URLSession(configuration: config)) {
            "test-token"
        }
    }

    private func request() -> ChatRequest {
        ChatRequest(model: "command-a-plus-05-2026", messages: [.user("hi")], stream: true)
    }

    @Test func non2xxThrowsHTTPErrorWithDecodedBodyAndRetryAfter() async throws {
        StubURLProtocol.stub = .init(
            status: 429,
            headers: ["Retry-After": "30", "Content-Type": "application/json"],
            body: Data(#"{"id":"req-1","message":"rate limit exceeded"}"#.utf8)
        )
        defer { StubURLProtocol.stub = nil }

        do {
            _ = try await makeTransport().stream(request(), baseURL: baseURL)
            Issue.record("expected the transport to throw on a 429")
        } catch let TransportError.httpError(status, body, retryAfter) {
            #expect(status == 429)
            #expect(body?.message == "rate limit exceeded")
            #expect(retryAfter != nil)
        }
    }

    @Test func successResponseStreamsBytesParseableAsEvents() async throws {
        let sse = """
            data: {"type":"message-start","id":"req-9"}

            data: {"type":"message-end","delta":{"finish_reason":"COMPLETE","usage":{"tokens":{"input_tokens":3,"output_tokens":4}}}}


            """
        StubURLProtocol.stub = .init(
            status: 200,
            headers: ["Content-Type": "text/event-stream"],
            body: Data(sse.utf8)
        )
        defer { StubURLProtocol.stub = nil }

        var parser = ChatStreamParser()
        var events: [ChatStreamEvent] = []
        for try await chunk in try await makeTransport().stream(request(), baseURL: baseURL) {
            events += parser.feed(chunk)
        }
        events += parser.finish()

        guard case .messageStart(let id) = try #require(events.first) else {
            Issue.record("expected message-start first"); return
        }
        #expect(id == "req-9")
        guard case .messageEnd(let reason, let usage) = try #require(events.last) else {
            Issue.record("expected message-end last"); return
        }
        #expect(reason == .complete)
        #expect(usage?.tokens?.outputTokens == 4)
    }
}
