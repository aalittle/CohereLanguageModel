# CohereLanguageModel

Cohere's Command models in Apple's Foundation Models framework — a `LanguageModel` protocol conformance with first-class citation support.

> **Status: pre-release, built in the open.** Nothing here is stable yet. Follow along via the [issues](https://github.com/aalittle/CohereLanguageModel/issues) and the [development plan](DEVELOPMENT_PLAN.md); the why lives in the [PRD](prd-cohere-language-model-package.md).

## What this will be

Swap Apple's on-device model for Cohere's Command A+ by changing one initializer — same `LanguageModelSession`, same tools, same streaming:

```swift
// Planned API — not yet implemented
let model = CohereLanguageModel(configuration: .init(tokenProvider: myProvider))
let session = LanguageModelSession(model: model)
let response = try await session.respond(to: "How often does P-301 need lubrication?")
```

The differentiator: Cohere streams **native citations** (character offsets, cited text, source documents) with grounded responses, and this package surfaces them through Apple's response-metadata channel.

## Package layout

| Module | Contents | Requires |
|---|---|---|
| `CohereAPI` | Chat V2 wire types, SSE parser, HTTP transport | Foundation only |
| `CohereLanguageModel` | The Foundation Models adapter | iOS 27 / macOS 27 SDK |

Zero third-party dependencies.

## Privacy

**This is a cloud-based model: prompts, transcripts, and grounding documents leave the device** and are processed by Cohere (or by your own Cohere deployment when using a custom base URL). If you need on-device inference, Apple's MLX path can run the open-weight [Command A+](https://huggingface.co/CohereLabs/command-a-plus-05-2026) locally — different trade-offs, no package required.

## Requirements

- Xcode 27 beta (iOS 27 / macOS 27 SDK) for the adapter module
- A Cohere API key — the documented auth path is a token provider with Keychain persistence; raw key strings are for prototyping only

## Authentication

Per Apple's guidance, the package never takes an API key as a permanent initializer string. The documented path is a `TokenProvider`:

```swift
// Prototyping — fine for a spike, not for shipping.
let config = CohereLanguageModel.Configuration(apiKey: "sk-...")

// Production — fetch a short-lived token from your backend and persist it.
let provider = PersistingTokenProvider(
    account: "cohere",
    store: KeychainTokenStore()
) {
    try await myBackend.fetchCohereToken()  // gate this with App Attest
}
let config = CohereLanguageModel.Configuration(tokenProvider: provider)
```

Tokens persist in the Keychain only — never in source, logs, URL parameters, or `UserDefaults`. The token is read per request and attached as an `Authorization: Bearer` header.

> **App Attest (production):** mint tokens server-side and require a valid [App Attest](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity) assertion before issuing one, so tampered builds can't reach your Cohere quota. A full walkthrough lands with the v1 docs (#14).

## License

[Apache 2.0](LICENSE) — matching Cohere's own Command A+ open-weights release.
