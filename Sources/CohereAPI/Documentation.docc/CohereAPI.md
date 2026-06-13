# ``CohereAPI``

A pure-Foundation client for Cohere's Chat V2 API: wire types, an incremental
SSE parser, and a streaming HTTP transport.

## Overview

`CohereAPI` is the transport and protocol layer beneath ``CohereLanguageModel``.
It has no dependency on Apple's Foundation Models framework, so it builds on any
recent Swift toolchain and stays portable toward a future Linux core.

Most apps use it indirectly through the adapter. Reach for it directly when you
want to speak Chat V2 without the Foundation Models layer — building a request,
streaming a response, and reading typed events:

```swift
import CohereAPI

let transport = URLSessionChatTransport { try await myTokenProvider.token() }
let request = ChatRequest(
    model: "command-a-plus-05-2026",
    messages: [.user("Summarize the P-301 service log.")],
    stream: true
)

var parser = ChatStreamParser()
for try await chunk in try await transport.stream(request, baseURL: CohereAPI.defaultBaseURL) {
    for event in parser.feed(chunk) {
        // handle .contentDelta, .citationStart, .messageEnd, ...
    }
}
```

Unknown SSE event types decode as ``ChatStreamEvent/unknown(type:)`` and are
logged rather than thrown, so a new server event kind never breaks the stream.

## Topics

### Requests and responses

- ``ChatRequest``
- ``ChatMessage``
- ``ChatResponse``
- ``AssistantMessage``
- ``ContentBlock``
- ``Citation``
- ``Usage``
- ``FinishReason``

### Tools and documents

- ``ToolDefinition``
- ``ToolCall``
- ``Document``
- ``ResponseFormat``
- ``JSONValue``

### Streaming

- ``ChatStreamEvent``
- ``ChatStreamParser``
- ``ChatStreamEventDecoder``
- ``SSEParser``

### Transport

- ``ChatTransport``
- ``URLSessionChatTransport``
- ``TransportError``

### Authentication

- ``TokenProvider``
- ``StaticTokenProvider``
- ``PersistingTokenProvider``
- ``UnauthenticatedTokenProvider``
- ``TokenStore``
- ``InMemoryTokenStore``
- ``KeychainTokenStore``
- ``KeychainError``
