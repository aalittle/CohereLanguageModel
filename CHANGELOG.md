# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] - 2026-06-13

Pre-publication hardening ahead of the first public release: documentation,
test coverage, and repository polish. No source-breaking changes to the
public API.

### Added

- DocC catalogs for both modules and Swift Package Index doc hosting (`.spi.yml`).
- `SECURITY.md`, `CONTRIBUTING.md`, this changelog, and issue/PR templates.
- `NOTICE` with copyright and trademark attribution.
- Tests for `KeychainTokenStore` (via an injectable backend seam), the
  `URLSession` transport's HTTP error and streaming paths, and the SSE
  decoder's skip-on-missing-field guarantees.

### Changed

- `URLSessionChatTransport` stored properties are now `private`;
  `ToolDefinition.type` and `ToolCall.type` are immutable.
- The streaming request sends `Accept: text/event-stream`.

### Fixed

- Unknown SSE event types are now logged at `.debug` (NFR-5) rather than
  skipped silently.
- The HTTP error-body buffer is capped to avoid an unbounded read.
- Removed dead per-index state from the stream translator.

## [1.0.0] - 2026-06-13

Initial release. Cohere's Command models as an Apple Foundation Models
`LanguageModel`, in two modules with a strict boundary.

### Added

- **`CohereLanguageModel`** — a `LanguageModel` conformance and streaming
  executor that drop-in replaces `SystemLanguageModel` in a
  `LanguageModelSession` (iOS 27 / macOS 27).
- **`CohereAPI`** — a pure-Foundation Cohere Chat V2 client: Codable wire
  types, an incremental SSE parser tolerant of unknown event types, and a
  `URLSession`-backed streaming transport. No FoundationModels dependency,
  so it stays portable toward a future Linux core.
- Transcript translation across all Foundation Models entry types, including
  `thinking` blocks routed to the reasoning channel.
- `GenerationOptions` pass-through and mapping of Cohere/network failures onto
  the framework's built-in `LanguageModelError` cases.
- Authentication via an injected `TokenProvider`, with Keychain persistence
  (`KeychainTokenStore`) and a prototyping string-key convenience. Tokens are
  read per request and never logged.
- Configurable `baseURL` for VPC, on-premises, or air-gapped Cohere
  deployments.

[1.0.1]: https://github.com/aalittle/CohereLanguageModel/releases/tag/1.0.1
[1.0.0]: https://github.com/aalittle/CohereLanguageModel/releases/tag/1.0.0
