import Foundation

/// Incremental Server-Sent Events framing: feed raw bytes as they arrive,
/// get back completed `data:` payloads. Handles events split across chunk
/// boundaries, LF and CRLF line endings, multi-line `data:` fields (joined
/// with newlines per the SSE spec), and ignores comment lines and fields
/// this client doesn't use (`event:`, `id:`, `retry:`).
///
/// This layer knows nothing about Cohere: it turns bytes into payload
/// strings. ``ChatStreamEventDecoder`` turns payloads into typed events.
public struct SSEParser: Sendable {
    private var buffer = Data()
    private var dataLines: [String] = []

    public init() {}

    /// Consume the next chunk and return any data payloads it completed.
    public mutating func feed(_ chunk: Data) -> [String] {
        buffer.append(chunk)
        var payloads: [String] = []

        while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            var lineData = buffer[buffer.startIndex..<newlineIndex]
            if lineData.last == UInt8(ascii: "\r") {
                lineData = lineData.dropLast()
            }
            buffer.removeSubrange(buffer.startIndex...newlineIndex)

            let line = String(decoding: lineData, as: UTF8.self)
            if line.isEmpty {
                // Blank line dispatches the accumulated event.
                if !dataLines.isEmpty {
                    payloads.append(dataLines.joined(separator: "\n"))
                    dataLines.removeAll()
                }
            } else if line.hasPrefix("data:") {
                var value = line.dropFirst("data:".count)
                if value.first == " " { value = value.dropFirst() }
                dataLines.append(String(value))
            }
            // Comments (":...") and other fields are intentionally ignored.
        }
        return payloads
    }

    /// Flush any final event not followed by a blank line (stream ended).
    public mutating func finish() -> [String] {
        guard !dataLines.isEmpty else { return [] }
        defer { dataLines.removeAll() }
        return [dataLines.joined(separator: "\n")]
    }
}
