# CohereLanguageModel

Cohere's Command models as an Apple Foundation Models `LanguageModel` — a drop-in replacement for `SystemLanguageModel` with first-class citation support.

> **Requires Xcode 27 beta / iOS 27 / macOS 27 SDK.**

```swift
import FoundationModels
import CohereLanguageModel

let model = CohereLanguageModel(configuration: .init(tokenProvider: myProvider))
let session = LanguageModelSession(model: model)
let response = try await session.respond(to: "How often does P-301 need lubrication?")
print(response.content)
```

## Quickstart (~15 minutes)

### 1. Add the package

In Xcode: **File › Add Package Dependencies**, enter the repository URL, and add both `CohereAPI` and `CohereLanguageModel` to your target.

### 2. Store your API key

Never put keys in source. Store yours in the Keychain once:

```sh
security add-generic-password \
  -s com.aalittle.CohereLanguageModel \
  -a cohere \
  -w          # prompts for the key
```

### 3. Configure authentication

```swift
import CohereAPI
import CohereLanguageModel

let provider = PersistingTokenProvider(
    account: "cohere",
    store: KeychainTokenStore()
) {
    // Fetch a short-lived token from your backend.
    // Gate this with App Attest — see "Security" below.
    try await myBackend.fetchCohereToken()
}

let config = CohereLanguageModel.Configuration(tokenProvider: provider)
let model = CohereLanguageModel(configuration: config)
```

**Prototyping only** (never ship this):

```swift
let model = CohereLanguageModel(configuration: .init(apiKey: "sk-..."))
```

### 4. Start a session

```swift
let session = LanguageModelSession(model: model)
```

This is identical to the `SystemLanguageModel` path — same `LanguageModelSession`, same tool-calling APIs, same structured output support.

### 5. Ground responses with documents

Pass source documents and Cohere returns citations that map response spans back to their sources:

```swift
// Citations arrive through response metadata (no special API needed).
let response = try await session.respond(
    to: "What does the manual say about lubrication intervals?"
)
// Response text is grounded; citation metadata is in the response.
```

Documents and citation wiring land in issue [#15](https://github.com/aalittle/CohereLanguageModel/issues/15).

### 6. Override the endpoint

Point at a VPC or on-premises Cohere deployment by passing a custom `baseURL`:

```swift
let config = CohereLanguageModel.Configuration(
    tokenProvider: myProvider,
    baseURL: URL(string: "https://cohere.internal.example.com")!
)
```

The package is identity-agnostic — it sends a Chat V2 request and parses the response; the endpoint decides what runs.

## Package layout

| Module | Contents | Requires |
|---|---|---|
| `CohereAPI` | Chat V2 wire types, SSE stream parser, HTTP transport | Foundation only |
| `CohereLanguageModel` | Foundation Models adapter | iOS 27 / macOS 27 SDK |

Zero third-party dependencies.

## Privacy

**This is a cloud model: prompts, transcripts, and grounding documents leave the device** and are processed by Cohere (or by your private deployment when using a custom `baseURL`). Disclose this in your app's privacy manifest under "Other data types — user-generated content."

For purely on-device inference with the same open weights, Cohere's [Command A+](https://huggingface.co/CohereLabs/command-a-plus-05-2026) is available on Hugging Face and can be run locally via Apple's MLX framework — different hardware requirements, no package required.

## Security

**Tokens, never keys.** The documented production path is a `TokenProvider` that exchanges a device credential for a short-lived API token:

1. Your app attests its identity with [App Attest](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity) (`DCAppAttestService`).
2. Your backend verifies the assertion and mints a Cohere-scoped token with a short TTL.
3. The app stores the token in the Keychain via `PersistingTokenProvider` + `KeychainTokenStore`.
4. The token is read per request and sent as `Authorization: Bearer`; it is never logged.

Tokens are stored under `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` and are never synced to iCloud or other devices.

## Requirements

- Xcode 27 beta (`CohereLanguageModel` target) — `CohereAPI` builds on stock toolchains
- iOS 27 / macOS 27 deployment target for the adapter
- A Cohere API key or private deployment

## Development

See [DEVELOPMENT_PLAN.md](DEVELOPMENT_PLAN.md) for the milestone breakdown and the [issues](https://github.com/aalittle/CohereLanguageModel/issues) for current work. The PRD is at [prd-cohere-language-model-package.md](prd-cohere-language-model-package.md).

## License

[Apache 2.0](LICENSE)

---

Cohere is a trademark of Cohere Inc. This package is not affiliated with or endorsed by Cohere.
