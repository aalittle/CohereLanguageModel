// swift-tools-version: 6.2
// SPIKE ONLY (issue #3) — throwaway manifest, not the real package layout.
import PackageDescription

let package = Package(
    name: "CohereLanguageModelSpike",
    platforms: [
        .macOS("27.0"),
        .iOS("27.0"),
    ],
    targets: [
        .target(name: "CohereLanguageModelSpike")
    ]
)
