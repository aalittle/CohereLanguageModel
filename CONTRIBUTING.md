# Contributing

Thanks for your interest in the project. It's built in the open, one issue at a time, and contributions are welcome.

## Workflow

- Every change traces to a GitHub issue. If one doesn't exist for what you want to do, open it first so we can agree on the approach before code is written.
- One issue is one PR is one self-contained change. PRs target 200–400 changed lines; split before exceeding that.
- Don't bundle unrelated changes (refactors, cleanups, drive-by fixes) into a feature PR.
- `main` is protected. All changes, docs included, go through a pull request.

## Building and testing

The package has two targets:

- **`CohereAPI`** — the Chat V2 client (wire types, SSE parser, transport). Pure Foundation. Builds and tests on any recent Swift toolchain.
- **`CohereLanguageModel`** — the Foundation Models adapter. Requires the **Xcode 27 beta** (iOS 27 / macOS 27 SDK); it's gated with `#if compiler(>=6.4)` so the package still builds on stock toolchains, where it compiles to an empty module.

Stock toolchain (what CI runs):

```sh
swift test
```

Adapter target, on the beta toolchain:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app swift test \
  --scratch-path "$HOME/.cache/swiftpm-scratch/CohereLanguageModel"
```

The `--scratch-path` keeps build products out of any iCloud-synced directory, which otherwise breaks codesigning of the test bundle.

## Standards

- Swift strict concurrency `complete`; the package must build warning-free.
- Value types by default; typed, contextful errors; enums over flat optionals.
- Explicit access control everywhere. `public` is a contract — default to `internal` and expose deliberately. Every `public` symbol gets DocC documentation before it merges.
- No API keys, tokens, or auth headers in source, logs, URLs, or fixture files.

## Tests

- Swift Testing (`@Test`, `@Suite`), not XCTest.
- Name tests by behavior, not method.
- Deterministic and fixture-driven: no network, no `Date()`/randomness in assertions. Mock at protocol boundaries.
- Live tests that hit the real Cohere API are opt-in behind `COHERE_LIVE_TESTS=1` and never run in CI.
