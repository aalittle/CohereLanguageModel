# ``CohereLanguageModel``

Cohere's Command models as an Apple Foundation Models language model.

## Overview

This module conforms Cohere's Chat V2 API to the Foundation Models
`LanguageModel` protocol, so Cohere's Command models drop into a
`LanguageModelSession` exactly where Apple's on-device `SystemLanguageModel`
would go — same session, same tools, same streaming.

```swift
import FoundationModels
import CohereLanguageModel

let model = CohereLanguageModel(
    configuration: .init(tokenProvider: myTokenProvider)
)
let session = LanguageModelSession(model: model)
let response = try await session.respond(to: "How often does P-301 need lubrication?")
```

Point ``CohereLanguageModel/Configuration/baseURL`` at a VPC, on-premises, or
air-gapped Cohere deployment to run identically against a private installation.

> Important: This is a cloud model. Prompts, transcripts, and grounding
> documents leave the device for the configured endpoint. The documented
> authentication path is a token provider with Keychain persistence; raw API
> keys are for prototyping only.

This module requires the iOS 27 / macOS 27 SDK. The underlying Chat V2 client
lives in ``CohereAPI``, which builds on any recent toolchain.

## Topics

### Essentials

- ``CohereLanguageModel/Configuration``
- ``CohereLanguageModelExecutor``
