// swift-tools-version: 6.1
// Tools version stays at 6.1 (nothing in this manifest needs newer) so CI
// runners trailing the latest Xcode can still build the core target.
import PackageDescription

// Platform floor is 26.0 so the CohereAPI core target builds on stock
// toolchains (and CI runners without the 27 beta). The FoundationModels
// adapter APIs are annotated @available(iOS 27.0, macOS 27.0, ...) instead.
let package = Package(
    name: "CohereLanguageModel",
    platforms: [
        .macOS("26.0"),
        .iOS("26.0"),
        .visionOS("26.0"),
        .watchOS("26.0"),
    ],
    products: [
        .library(name: "CohereLanguageModel", targets: ["CohereLanguageModel"]),
        .library(name: "CohereAPI", targets: ["CohereAPI"]),
    ],
    targets: [
        // Cohere Chat V2 client: wire types, SSE parser, HTTP transport.
        // Pure Foundation — must never import FoundationModels.
        .target(name: "CohereAPI"),

        // The Foundation Models adapter: LanguageModel conformance,
        // executor, transcript translation. Requires the iOS 27 SDK.
        .target(
            name: "CohereLanguageModel",
            dependencies: ["CohereAPI"]
        ),

        .testTarget(
            name: "CohereAPITests",
            dependencies: ["CohereAPI"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
