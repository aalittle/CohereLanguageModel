# What I learned building a third-party LanguageModel for Apple's Foundation Models framework

Apple announced Foundation Models at WWDC 2025, and with WWDC 2026 they opened the `LanguageModel` protocol so third-party models can plug into the same `LanguageModelSession` that runs Apple's on-device model. I spent a few weeks building `CohereLanguageModel`, a package that makes Cohere's Command A+ a drop-in replacement for `SystemLanguageModel`, and I want to share what I found along the way.

## Why Cohere

Cohere does something that most providers don't: when you ground a response with source documents, the model streams back citations with character offsets into the response text. You get the exact span that was grounded and which document backed it. That's the kind of structured output that makes a real difference in production apps, and I wanted to see if Apple's framework could carry it.

## The two-target split

The first design decision was splitting the package into two Swift modules. `CohereAPI` is pure Foundation, no FoundationModels import, and it handles the Chat V2 wire types, SSE stream parsing, and HTTP transport. `CohereLanguageModel` is the adapter that conforms to the protocol and depends on the iOS 27 / macOS 27 SDK.

The reason this matters is that the beta SDK is required for the adapter, but CI runners don't have it yet. With the split, the entire API layer builds and tests on stock toolchains. I gate the adapter with `#if compiler(>=6.4)` so it compiles to nothing on older Xcode, and the package still builds everywhere. Once Xcode 27 goes GM, the gate comes off and nothing else changes.

## The push model

The protocol's streaming design surprised me. You don't return an `AsyncSequence`. The framework hands you a `LanguageModelExecutorGenerationChannel` and you push events into it with `channel.send()`. So your executor's `respond` method is `nonisolated(nonsending)`, and you're calling an async `send` for every text fragment, every reasoning block, every usage update. It's a fundamentally different shape than what you'd build if you were designing a streaming API from scratch.

I kept the translator framework-free because of this. `StreamTranslator` takes SSE events and produces a simple `Action` enum (`.appendText`, `.appendReasoning`, `.usage`, `.finished`), and then the executor replays those actions onto the channel. This means I can test the entire translation pipeline against recorded fixtures without constructing any 27-only channel objects.

## Command A+ reasons before it answers

This one cost me a live test failure. I set `maxTokens: 16` expecting a short reply, and the model spent all 16 tokens on a thinking block and emitted no text at all. Command A+ reasons before answering, and the reasoning comes as `thinking` content blocks interleaved with `text` blocks. With a tight token budget, the model runs out of room before it starts talking.

I bumped the live test to 256 tokens and made the assertion accept any content delta type, not just text. But the bigger lesson is that token budgets mean something different when the model has a reasoning phase you can't turn off. Your users will hit this if you expose a token limit control.

## Late usage is a documented deviation

Apple's recommended event order is metadata, then usage, then text deltas. Cohere reports usage only at `message-end`, which means usage arrives after the last text delta, not before. I documented this as a deliberate deviation and emit usage right before the `.finished` action. It works fine in practice because the framework doesn't enforce ordering, but it's the kind of thing that would bite you if you assumed the recommended order was the only valid order.

## Token counts per fragment

The framework wants a `tokenCount` with every `appendText` call. Cohere doesn't report per-delta token counts, so I send `tokenCount: 0` for every fragment and then report accurate totals in the `updateUsage` call at the end of the stream. This is an honest representation of what the API actually provides, and the framework handles it correctly.

## What I'd tell another implementor

If you're building a third-party `LanguageModel` provider, here's what I'd focus on:

- Split your package so the wire layer is testable without the beta SDK. You will spend a lot of time on the wire layer, and you want fast iteration there.
- Record real SSE fixtures early. My fixture capture script makes five Cohere API calls, and every test after that runs against those recordings. No network in CI, ever.
- Keep your stream translator framework-free. The channel is an implementation detail of the executor. Your translation logic is the interesting part, and you want to test it independently.
- Be explicit about where you deviate from Apple's recommended patterns. Document it, test for it, and move on. The protocol is flexible enough to accommodate real-world APIs.
- Test with generous token budgets. If your model reasons before responding, a tight budget produces surprising results.

## Where this goes next

The citation support is the feature I'm most excited about. Cohere streams citations interleaved with text deltas, and surfacing them through response metadata would give developers something no other provider offers today. That's the next piece of work.

The package is open source at [github.com/aalittle/CohereLanguageModel](https://github.com/aalittle/CohereLanguageModel) if you want to look at the code or try integrating it yourself.
