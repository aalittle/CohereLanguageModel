# CohereLanguageModel

Swift package conforming Cohere's Chat V2 API to Apple's Foundation Models `LanguageModel` protocol (iOS 27 / macOS 27), with first-class citation support. Personal open source project under `aalittle`.

- **What & why:** [prd-cohere-language-model-package.md](prd-cohere-language-model-package.md)
- **How, in what order:** [DEVELOPMENT_PLAN.md](DEVELOPMENT_PLAN.md) — issue numbers there match GitHub issue numbers 1:1

## Toolchain — read this first

All builds require the **Xcode 27 beta**. The system-selected Xcode (26.1.1) does NOT have the `LanguageModel` / `LanguageModelExecutor` protocols and will fail to compile the adapter target.

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app swift build
DEVELOPER_DIR=/Applications/Xcode-beta.app swift test
```

Never run `xcode-select -s` globally; always use `DEVELOPER_DIR` per-invocation.

## Architecture

Two targets, strict boundary:

- **`CohereAPI`** — Chat V2 wire types, SSE parser, HTTP client. Pure Foundation. **Must never import FoundationModels.** Testable on any toolchain; future Linux core.
- **`CohereLanguageModel`** — the FoundationModels adapter: protocol conformance, executor, transcript translation. Depends on `CohereAPI`, never the reverse.

Zero third-party dependencies (NFR-2). URLSession and Foundation only. If you think you need a dependency, you don't.

## Workflow

- Work happens in the open: every change traces to a GitHub issue; one issue = one PR = one self-contained change
- PRs target 200–400 changed lines; split before exceeding
- No feature PR bundles refactors, cleanups, or drive-by fixes
- Issue #1 (Cohere official-package check) gates feature commits; spikes on throwaway branches are exempt
- Conformance tests run on recorded SSE fixtures — no network in CI. Live tests are opt-in behind an env var

## Swift standards

Swift 6.2, API Design Guidelines naming. Specifics this project holds itself to:

**Concurrency**
- Strict concurrency `complete`; the package must be warning-free
- Structured concurrency only — no `DispatchQueue`, no detached tasks without justification
- `Sendable` conformance is deliberate, not reflexive; `@unchecked Sendable` requires a comment documenting the safety invariant it relies on

**Types & state**
- Value types by default; classes only where reference semantics are the point
- Enums with associated values over flat optionals — make illegal states unrepresentable. The SSE event vocabulary and stream state machine are enums, not string-typed switches
- No stringly-typed keys; constants get a type

**Errors**
- Typed domain errors carrying context; map to the framework's built-in `LanguageModelError` cases first, custom cases only for Cohere-specific failures (FR-6)
- Never silently swallow errors. The one documented exception (NFR-5): unknown SSE event types are *skipped*, but always with a `.debug` log — skipping silently and crashing are both bugs

**Observability**
- `OSLog.Logger` with subsystem `com.aalittle.CohereLanguageModel` and per-component categories; never `print()`
- Use privacy levels; prompt/response content is `.private`
- **Never log tokens, API keys, or auth headers at any level** (NFR-4)

**API surface & docs**
- Explicit access control everywhere — this is a library; `public` is a contract. Default to `internal`, expose deliberately
- Every `public` symbol has DocC documentation before it merges
- No singletons in public API; dependencies (token provider, transport) are injected via protocol boundaries so tests can substitute fakes

**Testing**
- Swift Testing framework (`@Test`, `@Suite`), not XCTest
- Test names state behavior ("emitsMetadataBeforeFirstTextDelta"), not method names
- Deterministic: fixture-driven, no `Date()`/randomness in assertions, no network
- Mock at protocol boundaries; if something can't be faked, the boundary is wrong

**Security**
- No API keys in source, logs, URL parameters, or fixture files — scrub captured fixtures before committing
- Tokens persist in Keychain only; documented auth path is the token provider, not raw key strings

## Gotchas

- `swift-best-practices-audit.md` in this folder is an audit of a *different* project (Daily Pulse); it's reference material, untracked — do not commit it
- Apple's recommended event order is metadata → usage → text deltas; Cohere reports usage only at message-end, so usage is emitted late by design — documented deviation (FR-14)
- Citations arrive interleaved with text deltas but reference offsets in the complete response; citation timing is a deliberate design decision (issue #17), don't improvise it
