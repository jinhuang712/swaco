// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swaco",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "Swaco", targets: ["Swaco"]),
        .library(name: "SwacoAI", targets: ["SwacoAI"]),
        .library(name: "SwacoOpenAI", targets: ["SwacoOpenAI"]),
        .library(name: "SwacoInteraction", targets: ["SwacoInteraction"]),
        .library(name: "SwacoRuntime", targets: ["SwacoRuntime"]),
        .library(name: "SwacoTesting", targets: ["SwacoTesting"]),
    ],
    targets: [
        .target(name: "Swaco"),

        // The AI layer: shared machinery, then one thin target per vendor.
        .target(name: "SwacoAI", dependencies: ["Swaco"], path: "Sources/SwacoAI/Core"),
        .target(name: "SwacoOpenAI", dependencies: ["SwacoAI"], path: "Sources/SwacoAI/OpenAI"),

        .target(name: "SwacoInteraction", dependencies: ["Swaco"]),
        .target(name: "SwacoRuntime", dependencies: ["Swaco"]),

        // Public, so companions and third parties run the same contracts.
        .target(name: "SwacoTesting", dependencies: ["Swaco"]),

        .testTarget(name: "SwacoTests", dependencies: ["Swaco", "SwacoTesting"]),
        .testTarget(name: "SwacoRuntimeTests", dependencies: ["SwacoRuntime", "SwacoTesting"]),
        .testTarget(name: "SwacoInteractionTests",
                    dependencies: ["SwacoInteraction", "SwacoRuntime", "SwacoTesting"]),
        .testTarget(name: "SwacoAITests", dependencies: ["SwacoAI", "SwacoOpenAI"],
                    resources: [.copy("Fixtures")]),

        // The canonical first program, built in CI so it never drifts.
        .executableTarget(name: "FirstProgram", dependencies: ["Swaco", "SwacoOpenAI"],
                          path: "Examples/FirstProgram"),
    ]
)
