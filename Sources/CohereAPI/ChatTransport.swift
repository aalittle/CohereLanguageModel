import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends a Chat V2 request and yields raw response bytes as they arrive.
/// The executor injects a fixture-backed transport in tests; production
/// uses ``URLSessionChatTransport``.
public protocol ChatTransport: Sendable {
    func stream(
        _ request: ChatRequest, baseURL: URL
    ) async throws -> AsyncThrowingStream<Data, any Error>
}

/// Transport-level failures, mapped onto framework error cases by the
/// executor (#11 completes the mapping).
public enum TransportError: Error {
    /// Non-2xx HTTP status. `body` is the decoded Cohere error message
    /// when one was present.
    case httpError(statusCode: Int, body: APIErrorBody?, retryAfter: Date?)
    case missingCredentials
}

/// URLSession-backed SSE transport.
///
/// Authorization is supplied by an async provider closure so credentials
/// are fetched per-request and never stored here. #12 layers the public
/// token-provider API (with Keychain persistence) on top of this hook.
public struct URLSessionChatTransport: ChatTransport {
    private let session: URLSession
    private let authorization: @Sendable () async throws -> String

    public init(
        session: URLSession = .shared,
        authorization: @escaping @Sendable () async throws -> String
    ) {
        self.session = session
        self.authorization = authorization
    }

    public func stream(
        _ request: ChatRequest, baseURL: URL
    ) async throws -> AsyncThrowingStream<Data, any Error> {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("v2/chat"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.setValue(
            "Bearer \(try await authorization())", forHTTPHeaderField: "Authorization"
        )
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (bytes, response) = try await session.bytes(for: urlRequest)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // Cap the error body: a misbehaving endpoint or proxy could stream
            // an unbounded response, and we only need the Cohere error JSON.
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count >= 16_384 { break }
            }
            throw TransportError.httpError(
                statusCode: http.statusCode,
                body: try? JSONDecoder().decode(APIErrorBody.self, from: body),
                retryAfter: (http.value(forHTTPHeaderField: "Retry-After"))
                    .flatMap(Self.retryAfterDate(from:))
            )
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var buffer = Data()
                    for try await byte in bytes {
                        buffer.append(byte)
                        if buffer.count >= 512 {
                            continuation.yield(buffer)
                            buffer = Data()
                        }
                    }
                    if !buffer.isEmpty { continuation.yield(buffer) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// `Retry-After` is either delta-seconds or an HTTP date.
    static func retryAfterDate(from value: String) -> Date? {
        if let seconds = TimeInterval(value) {
            return Date(timeIntervalSinceNow: seconds)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value)
    }
}
