# Development Plan: CohereLanguageModel

Companion to [prd-cohere-language-model-package.md](prd-cohere-language-model-package.md). Breaks the PRD into GitHub issues, each scoped to one small PR (target 200–400 changed lines).

## Working agreements

- One issue = one PR = one self-contained change
- Issues labeled by milestone (`m0`–`m4`) and priority (`p0`/`p1`/`p2`)
- `user-action` label for items only Andrew can do (outreach, accounts, naming)
- No feature PR bundles refactors or cleanups
- All toolchain commands use `DEVELOPER_DIR=/Applications/Xcode-beta.app` (Xcode 27 beta)

## Architecture note that shapes the breakdown

Split the package into two targets:

- **`CohereAPI`** — Chat V2 wire types, SSE parser, HTTP client. Pure Foundation, no FoundationModels import. Testable on any toolchain; becomes the Linux-compatible core later (NFR-3).
- **`CohereLanguageModel`** — the FoundationModels adapter: `LanguageModel` conformance, executor, transcript translation. Requires the iOS 27 / macOS 27 SDK.

This keeps CI green even before GitHub Actions runners carry the Xcode 27 beta, and isolates Apple-protocol churn (PRD risk #2) from the stable Cohere client.

---

## M0: Validate — Week 1

| # | Issue | Scope | Exit criteria |
|---|---|---|---|
| 1 | Confirm no official Cohere package in flight | `user-action`, **blocking** (PRD Q1) | Cohere contact reply, or 1-week timeout → proceed |
| 2 | Naming / trademark check | `user-action` (PRD Q4) | Package name decided per Cohere brand guidelines |
| 3 | Protocol spike | Empty `LanguageModel` + `LanguageModelExecutor` conformance compiles against beta SDK; throwaway branch | Compiles; protocol surface notes captured for the blog post |
| 4 | Trial-tier validation + fixture capture | Live calls: basic chat, streamed chat, document-grounded request with citations. Save raw SSE as test fixtures (PRD Q5) | Fixtures committed; rate-limit reality documented |

Issue 4 produces the recorded fixtures every later test depends on — do it early.

## M1: v1 release — Weeks 2–4 (FR-1 → FR-8)

| # | Issue | Scope | FR/NFR |
|---|---|---|---|
| 5 | Package scaffold | SPM manifest (two targets), MIT/Apache license, README stub, `.gitignore`, GitHub Actions CI (build + test `CohereAPI` on stock toolchain; beta-SDK job added when runners support it) | NFR-2 |
| 6 | Chat V2 wire types | Codable request/response models: messages, roles, tools, documents, response_format. No networking | FR-2 (prep) |
| 7 | SSE parser | Incremental stream-event decoder; unknown events skipped with debug log; malformed-event tolerance; fixture-driven tests | NFR-5, NFR-6 |
| 8 | `CohereLanguageModel` + `Configuration` | Protocol conformance, capabilities declaration, Hashable Configuration with model ID + custom base URL | FR-1, FR-8 |
| 9 | Transcript translation | Six Apple entry types → Cohere roles, lossless; pure functions, table-driven tests | FR-3 |
| 10 | Streaming executor | SSE events → framework events; metadata update (request ID) before first text delta; no delta buffering | FR-2, FR-4, NFR-1 |
| 11 | Options + error mapping | GenerationOptions passthrough; Cohere/network errors → built-in `LanguageModelError` cases; throw on unsatisfiable options | FR-5, FR-6, NFR-5 |
| 12 | Auth: token provider | Token-provider injection, Keychain persistence, prototyping string-key convenience init; no keys in logs/URLs | FR-7, NFR-4 |
| 13 | Conformance suite + live test | Fixture-driven suite for all basic chat scenarios; opt-in live test behind env var | NFR-6 |
| 14 | v1 polish + release | DocC on public API, README 15-minute quickstart, privacy disclosure, App Attest notes, tag `1.0.0` | NFR-4, NFR-7 |

Dependencies: 5 → 6 → 7 → 10; 8, 9 independent after 5; 11, 12 after 10; 13, 14 last.

## M2: Writing — Weeks 5–6

| # | Issue | Scope |
|---|---|---|
| 15 | Implementation-notes blog post | Protocol learnings, gaps found, design decisions (citation timing, late usage, target split). Draft from notes accumulated in issues 3–14 |

## M3: v2 release — Weeks 7–8 (FR-9 → FR-12)

| # | Issue | Scope | FR |
|---|---|---|---|
| 16 | Tool calling | Tool definitions as JSON Schema; tool-plan-delta → reasoning delta; tool-call start/delta/end → toolCallDelta | FR-9 |
| 17 | Citation timing prototype | Spike both designs — retroactive segment-ID update vs. attach-at-content-end; measure perceived latency; record decision (PRD Q2) | FR-10 (prep) |
| 18 | Citation metadata | Winning design from #17: citations as metadata on text segments, typed accessors | FR-10 |
| 19 | Response schemas | ContextOptions schema → Cohere response_format | FR-11 |
| 20 | Demo app | Model swap, streamed responses, tappable rendered citations | FR-12 |

## M4: Cohere conversation — Week 9

| # | Issue | Scope |
|---|---|---|
| 21 | Share with Cohere | `user-action`: package + honest market assessment (PRD Appendix C) to Cohere contact |

## Deferred (PRD P2 / open questions)

- Documents-based RAG via custom segment (FR-13)
- Usage reporting at stream end (FR-14)
- Linux conformance — wait for Apple's summer open-source release (PRD Q3); the `CohereAPI` target split keeps the door open
- Server-side tools / connectors (out of scope until v3)

## Risk checkpoints

- **After issue 3:** if the beta protocol surface differs materially from the PRD's description, revise FR-2/FR-4 before building the executor
- **After issue 4:** if trial-tier rate limits can't support a citation demo, raise it in the M4 conversation early
- **At GM (fall):** one revision pass over the adapter target expected; wire types and parser should be untouched
