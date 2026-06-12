# PRD: CohereLanguageModel Swift Package for Apple's Foundation Models Framework

**Author:** Andrew Little
**Status:** Draft v1
**Date:** June 12, 2026
**Type:** Personal open source project

---

## 1. Executive summary

At WWDC 2026, Apple opened the Foundation Models framework to third-party LLM providers through a public LanguageModel protocol. Anthropic and Google are shipping official Swift packages for Claude and Gemini. Cohere has no presence in this ecosystem.

This project builds CohereLanguageModel, an open source Swift package that brings Cohere's Command models into the Foundation Models framework. Any Swift developer will be able to use Cohere models through the same LanguageModelSession API they use for Apple's on-device model, with one line changed.

The package's differentiator is first-class citation support. Cohere streams native citations with grounded responses, and Apple's framework has a metadata channel built for exactly this. No other announced provider package treats citations as a primary feature.

The primary goal is learning and reference value, not adoption. Realistic assessment: fewer than 10% of Cohere's enterprise customers need device-direct LLM access today. The project pays for itself in protocol-layer knowledge that transfers directly to a publishable artifact. Adoption is upside, not the bar.

## 2. Problem and opportunity

**Problem.** The Foundation Models framework launched with four model paths (on-device, Private Cloud Compute, Core AI, MLX) plus announced partner packages from Anthropic and Google. Developers who want Cohere's grounded, citation-rich responses in a native Apple app must today hand-roll URLSession code against Cohere's REST API, losing the framework's session management, transcript handling, model swapping, and tool protocol.

**Opportunity, sized honestly:**

1. **Ecosystem gap.** Apple explicitly invited third-party LanguageModel packages and is open sourcing the framework in summer 2026. No community-built provider package exists yet. The first clean implementation becomes the reference others copy.
2. **Differentiated capability.** Cohere's citation-start/citation-end stream events carry character offsets, cited text, and source documents. Apple's response metadata pattern is purpose-built to surface this. The combination produces something neither launch partner showcases: grounded, cited responses through a standard Apple API.
3. **Niche but real customer fit.** Regulated-industry field workforce apps (utilities, healthcare, field service) want cited answers from internal documentation in native apps, with on-device fallback when offline. The framework makes the fallback story one line of code. This segment is small but it is exactly the segment I understand.
4. **Personal strategic value.** Implementing the protocol builds direct knowledge of how iOS teams will consume once iOS 27 ships.

## 3. Goals and success metrics
| Goal | Metric | Target | Timeframe |
|---|---|---|---|
| Working v1 | Streaming text chat against Command A+ passes a conformance test suite | 100% of basic chat scenarios pass | 4 weeks from start |
| Developer experience | Time from "add package in Xcode" to first streamed response | Under 15 minutes following the README | At v1 release |
| Citation support (v2) | Citations attached to transcript segments and rendered in demo app | Working demo with character-accurate citation spans | 8 weeks from start |
| Reference value | Implementation guide published (blog post documenting protocol learnings, gaps found, design decisions) | 1 published piece | Within 2 weeks of v1 |
| Community signal (secondary) | GitHub stars, issues filed by non-author | 50 stars, 5 external issues | 6 months |
| Cohere conversation (secondary) | Package shared with a Cohere contact with the honest market assessment attached | 1 conversation | Within 4 weeks of v1 |

Explicitly not a goal: production adoption volume. If the package gets zero production users, the learning and writing outcomes still justify the investment.

## 4. Use cases

1. **Model swap.** A Swift developer building with SystemLanguageModel swaps to CohereLanguageModel by changing the model initializer. Session code, tool definitions, and streaming handling are unchanged.
2. **Grounded Q&A with citations.** A field service app passes internal documentation as documents to a Cohere-backed session. Responses stream with citation metadata the app renders as tappable source links.
3. **Offline fallback.** An app uses CohereLanguageModel when connected and falls back to SystemLanguageModel offline, through the same session API.
4. **Private deployment.** An enterprise running Cohere in their own VPC points the package at a custom base URL instead of Cohere's SaaS endpoint.
5. **Tool calling.** A developer registers tools on the session. Cohere's tool-plan and tool-call events stream through Apple's tool protocol; the app executes tools and returns outputs through the standard transcript.

## 5. Functional requirements
Priority: P0 = v1 blocker, P1 = v2, P2 = later.
**FR-1 (P0).** The package shall provide a CohereLanguageModel type conforming to Apple's LanguageModel protocol, declaring capabilities and producing a Hashable Configuration.
**FR-2 (P0).** The package shall provide a CohereLanguageModelExecutor conforming to LanguageModelExecutor, translating Apple transcript entries to Cohere Chat V2 messages and streaming responses back as framework events.
**FR-3 (P0).** The executor shall map all six Apple transcript entry types (instructions, prompt, response, tool call, tool output, reasoning) to Cohere's System, User, Assistant, and Tool roles with no lossy flattening.
**FR-4 (P0).** The executor shall stream responses via Cohere's SSE chat_stream endpoint, emitting a metadata update (request ID from message-start) before the first text delta, and emitting each content-delta as a textDelta the moment it arrives.
**FR-5 (P0).** The executor shall honor GenerationOptions (temperature, max tokens, sampling) by passing them through to the Cohere request, and shall throw a framework LanguageModelError when developer options cannot be satisfied.
**FR-6 (P0).** The executor shall map Cohere API errors to built-in LanguageModelError cases (rate limit, context overflow, refusal). Custom error cases are reserved for Cohere-specific failures only.
**FR-7 (P0).** The package shall accept a token provider rather than a raw API key string, with Keychain-backed persistence for fetched tokens. A convenience string-key initializer may exist for prototyping but the documented path is the token provider.
**FR-8 (P0).** The Configuration shall include a custom base URL so private VPC and on-prem Cohere deployments work identically to the SaaS endpoint.
**FR-9 (P1).** The executor shall support tool calling: tool definitions pass through as JSON Schema, tool-plan-delta events map to reasoning deltas, and tool-call-start/delta/end sequences map to toolCallDelta events.
**FR-10 (P1).** The executor shall forward Cohere citation events as metadata attached to the corresponding text segments, including character offsets, cited text, and source identifiers. The package shall provide typed accessors for citation metadata.
**FR-11 (P1).** The executor shall support ContextOptions response schemas via Cohere's response_format JSON Schema support.
**FR-12 (P1).** The package shall ship a demo app showing model swap, streamed responses, and rendered citations.
**FR-13 (P2).** The executor shall support documents-based RAG requests through a custom segment type, so developers can pass grounding documents directly in prompts.
**FR-14 (P2).** Usage reporting: token counts from message-end shall be emitted as a usage update at stream completion, with the deviation from Apple's recommended early-usage ordering documented.

## 6. Non-functional requirements
**NFR-1 Performance.** Time to first token shall add no more than 50ms of package overhead beyond Cohere API latency. Event translation shall not buffer text deltas (except as required for citation attachment, per the documented design decision).
**NFR-2 Footprint.** Zero third-party dependencies. URLSession and Foundation only. The package adds under 500KB to a developer's app.
**NFR-3 Platforms.** iOS 27, macOS 27, visionOS 27, watchOS 27, and Linux (for server-side Swift, given the framework is going open source).
**NFR-4 Security.** No API keys in source, logs, or URL parameters. Tokens persist in Keychain only. README documents App Attest integration for production use.
**NFR-5 Reliability.** All Cohere error responses and network failures map to typed errors. No crashes on malformed SSE events; unknown event types are skipped with a debug log.
**NFR-6 Maintainability.** Conformance test suite runs against recorded SSE fixtures (no network required for CI) plus an opt-in live test against the trial tier. Public API is documented with DocC.
**NFR-7 Privacy.** README states plainly that this is a cloud-based model: prompts leave the device. This follows Apple's guidance that package authors disclose privacy characteristics.
## 7. Dependencies and assumptions
1. **Apple framework availability.** The LanguageModel protocol ships in the iOS 27 / macOS 27 SDKs (beta available now). Open sourcing is announced for summer 2026 but not required for v1.
2. **Cohere API stability.** Chat V2 streaming event schema (message-start, content-delta, citation-start/end, tool events, message-end) remains stable. Cohere's free trial tier remains available for development.
3. **No official Cohere package in flight.** Assumption to validate before writing code: ping a Cohere contact. If they have one underway, pivot to contributing rather than building parallel.
4. **Model availability.** command-a-plus-05-2026 remains the flagship API model through the project window. Model ID is a configuration parameter, not hardcoded, to survive deprecations.
5. **Personal time.** Roughly two weekends for v1, two more for v2. No SFS Mobile resources involved; this is a personal project under my own GitHub account.

## 8. Out of scope

1. On-device Cohere inference. Local Command A+ runs through Apple's existing MLXLanguageModel path; this package is server-only. The README will note the MLX option.
2. Cohere Embed and Rerank APIs. Generation only.
3. Cohere V1 Chat API support.
4. Custom segments for new modalities (audio, image) in v1/v2.
5. Server-side tools (Cohere connectors such as managed web search) until v3 at earliest.
6. Any Salesforce or Einstein integration. This project informs that question; it does not answer it.

## 9. Open questions

1. Does Cohere have an official package planned? (Blocking; resolve before first commit.)
2. Citation timing design: attach citation metadata retroactively to already-streamed segments via segment ID updates, or accumulate and attach at content-end? Prototype both; pick the one with better perceived latency.
3. Does Apple's framework license (pre open source) permit Linux conformance now, or does Linux support wait for the summer release?
4. Trademark: can the package use "Cohere" in its name, or does it need a neutral name with Cohere in the description? Check Cohere's brand guidelines.
5. Does the trial tier rate limit allow a realistic demo (citations require document-grounded requests)?

## 10. Timeline and milestones

| Milestone | Content | Target |
|---|---|---|
| M0: Validate | Cohere contact pinged, trademark checked, Xcode beta protocol spike compiles | Week 1 |
| M1: v1 release | FR-1 through FR-8, conformance tests, README, tagged release | Week 4 |
| M2: Writing | Implementation-notes blog post published | Week 6 |
| M3: v2 release | Tool calling, citations, schemas, demo app (FR-9 through FR-12) | Week 8 |
| M4: Cohere conversation | Package plus honest market assessment shared | Week 9 |

Timeline assumes weekend-scale effort. Slips are acceptable; the milestones order the work, they do not commit dates to anyone.

## 11. Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Cohere ships an official package | Medium | Project becomes redundant | Validate first (M0). If in flight, contribute instead. Learning value survives either way. |
| Apple protocol changes before GM | Medium | Rework | Build against beta, keep translation layer thin, expect one revision pass at GM. |
| Citation offsets don't map cleanly to streamed segments | Medium | v2 feature degrades | Fallback: attach citations at content-end rather than retroactively. Document the tradeoff. |
| Cohere deprecates the model ID | Low | Broken examples | Model ID is configuration; README shows how to update. |
| Near-zero adoption | High | None to primary goals | Adoption is a secondary metric by design. Success is defined by learning and reference value. |
| Time availbility | Medium | Slipped milestones | No external commitments on dates. Project pauses cleanly at any milestone boundary. |

---

## Appendix A: Apple Foundation Models framework, what we're building on

This is the educational context for readers who did not watch the WWDC 2026 sessions.
**What the framework is.** Foundation Models is Apple's Swift API for language models, introduced at WWDC 2025 for Apple's on-device model and expanded at WWDC 2026 into a general abstraction over nearly any LLM, local or server-based. A developer creates a model, passes it into a LanguageModelSession, and calls respond. The session manages the conversation transcript, streaming, and tool calls. The framework ships with iOS 27, macOS 27, visionOS 27, and watchOS 27, and Apple announced it will be open sourced in summer 2026.
**The four built-in model paths:**
1. **System Language Model.** The on-device model behind Apple Intelligence, rebuilt for 2026 with better instruction following and image input. Free, private, offline.
2. **Private Cloud Compute.** Apple's server model with reasoning and a 32K context window, with Apple's privacy guarantees. No API key or account required.
3. **Core AI.** Run your own local model weights efficiently on the Apple Neural Engine.
4. **MLX.** Run open-weight models from the MLX community on Hugging Face by passing a model ID.

**The extension point this project uses.** Everything above conforms to a public LanguageModel protocol, and Apple invited third parties to ship their own conformances as Swift packages. Anthropic and Google announced official packages for Claude and Gemini. The protocol has two pieces:
- **LanguageModel** declares what the model can do (capabilities) and provides a Hashable Configuration.
- **LanguageModelExecutor** does the work: initialized from a Configuration, with a prewarm function for expensive setup and a respond function that receives the conversation transcript plus developer options and streams generation events back.
The Configuration is the cache key. The session stores one executor per unique configuration, so two model instances with identical configurations share an executor (and its connections or KV state). When the session deallocates, executors release automatically.
**Transcripts.** The framework hands the executor the full conversation on every call as a sequence of six entry types: instructions (developer system prompt), prompts (user messages), responses, tool calls, tool outputs, and reasoning. The executor translates these to whatever message format its inference engine speaks, and translates the engine's output back into streamed events: text deltas, tool call deltas, metadata updates, usage updates.
**Recommended event order.** Metadata first (model and request IDs for logging), usage second (prompt token counts for accounting), then text deltas as tokens arrive. Server APIs that report usage only at stream end, including Cohere's, deviate on the second point.
**Developer intent.** Each request carries ContextOptions (what goes in the prompt: reasoning level, response schema) and GenerationOptions (the decoder loop: temperature, sampling, max tokens). When the executor cannot honor an option, it approximates where honest or throws a framework LanguageModelError (context overflow, rate limit, refusal) that developers already know how to handle.
**Differentiation hooks.** The protocol gives provider packages two extension mechanisms. Response metadata attaches typed key-value data to response segments (Apple's own example is citations). Custom segments define entirely new typed content kinds that flow through prompts and responses, intended for new modalities and structured tool output.
**Auth guidance.** Apple's explicit recommendation: do not take API keys as initializer strings. Offer a token provider or sign-in flow, persist tokens in Keychain, and use App Attest to keep tampered builds off your service.
## Appendix B: The Cohere side, what we're integrating
**The company's position.** Cohere is an enterprise AI company whose differentiation is retrieval-augmented generation with native citations, multilingual coverage, and private deployment (VPC, on-prem, air-gapped). Their stack is purpose-built: Embed feeds vector stores, Rerank sharpens retrieval, Command generates grounded answers with inline citations. They sell to regulated industries, which is why deployment flexibility and grounding are first-class rather than add-ons.
**The model this package targets.** Command A+ (model ID command-a-plus-05-2026), released May 20, 2026. Key attributes:
1. 218B-parameter sparse Mixture-of-Experts architecture with 25B active parameters per token, which is why it serves efficiently relative to its size.
2. Apache 2.0 open weights on Hugging Face (CohereLabs/command-a-plus-05-2026), Cohere's first true Apache 2.0 release. The open license is why an MLX local path exists at all, though at roughly 110GB+ quantized it is Mac Studio territory, not laptop territory.
3. 128K context window, 48 languages.
4. Native citation grounding: pass documents with a request and the model returns citations with character offsets and source references, no prompt engineering required.
5. Unified tool use and reasoning, with reasoning spans and tool calls parsed as typed output.
6. Runs on as few as 2x H100 GPUs at W4A4 quantization, which is the basis of the sovereign and on-prem deployment pitch.
Also relevant: Command A (111B, 256K context) as the prior flagship, and Command R7B as a budget option at roughly $0.04/$0.15 per 1M tokens. The package treats model ID as configuration, so all of these work.
**The API surface we wrap.** Cohere Chat V2: a messages array with User, Assistant, Tool, and System roles, JSON Schema tool definitions, tool_call_ids linking calls to results, a documents parameter for grounding, response_format with optional JSON Schema, and SSE streaming.
**The streaming event vocabulary and how it maps to Apple's:**
| Cohere SSE event | Carries | Apple framework event |
|---|---|---|
| message-start | Request ID | Metadata update |
| content-start / content-end | Segment boundaries | Internal bookkeeping |
| content-delta | Next text chunk | textDelta |
| tool-plan-delta | Model's reasoning about tool use | Reasoning delta |
| tool-call-start | Tool name and call ID | toolCallDelta (open) |
| tool-call-delta | Argument fragments | toolCallDelta |
| tool-call-end | Call complete | toolCallDelta (close) |
| citation-start / citation-end | Offsets, cited text, sources | Citation metadata on text segment |
| message-end | Finish reason, token usage | Usage update + completion |
**Why the fit is unusually clean.** Both sides use four-role message models, JSON Schema for tools, and SSE streaming with typed events. The two pieces of genuine design work are citation timing (citations reference character offsets in the complete response but arrive interleaved with deltas) and the late usage report. Everything else is translation plumbing.
**Cost to develop.** Cohere offers a free rate-limited trial tier covering Command models, so v1 and v2 development and the demo app cost nothing. Production pricing for reference: flagship generation runs $2.50 input / $10 output per 1M tokens.
## Appendix C: Honest market assessment
Included so the PRD does not oversell its own premise. Cohere's customer base builds server-side systems: banks, healthcare, government, telcos running RAG and agents behind their own backends. Most enterprise mobile architectures route through the company's backend for auth, audit, and governance, which makes device-direct LLM calls an anti-pattern for exactly the buyers Cohere wins. Estimate: under 10% of Cohere customers would use this capability within two years.
Two segments break the pattern. First, field workforce apps in regulated industries wanting cited answers in native apps with offline fallback, the one scenario where this framework's model-swap story is uniquely cheap. Second, customers on private Cohere deployments, which FR-8 (custom base URL) exists to serve and which dissolves the architecture objection.
This is why the project is framed as education with publishable byproducts. The package is an option on a future where enterprise mobile AI grows, built two weekends ahead of demand rather than in response to it.
