// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swaco",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "Swaco", targets: ["Swaco"]),
        .library(name: "SwacoAI", targets: ["SwacoAI"]),
        .library(name: "SwacoOpenAI", targets: ["SwacoOpenAI"]),
        .library(name: "SwacoFoundationModels", targets: ["SwacoFoundationModels"]),
        .library(name: "SwacoExtensions", targets: ["SwacoExtensions"]),
        .library(name: "SwacoInteraction", targets: ["SwacoInteraction"]),
        .library(name: "SwacoRuntime", targets: ["SwacoRuntime"]),
        .library(name: "SwacoTesting", targets: ["SwacoTesting"]),
    ],
    targets: [
        .target(name: "Swaco", resources: [.copy("PrivacyInfo.xcprivacy")]),

        // The AI layer: shared machinery, then one thin target per vendor.
        .target(name: "SwacoAI", dependencies: ["Swaco"], path: "Sources/SwacoAI/Core",
                resources: [.copy("PrivacyInfo.xcprivacy")]),
        .target(name: "SwacoOpenAI", dependencies: ["SwacoAI"], path: "Sources/SwacoAI/OpenAI"),
        .target(name: "SwacoFoundationModels", dependencies: ["Swaco"],
                path: "Sources/SwacoAI/FoundationModels"),

        .target(name: "SwacoExtensions", dependencies: ["Swaco"], resources: [.copy("PrivacyInfo.xcprivacy")]),
        .target(name: "SwacoInteraction", dependencies: ["Swaco"], resources: [.copy("PrivacyInfo.xcprivacy")]),
        .target(name: "SwacoRuntime", dependencies: ["Swaco"], resources: [.copy("PrivacyInfo.xcprivacy")]),

        // Public, so companions and third parties run the same contracts.
        .target(name: "SwacoTesting", dependencies: ["Swaco", "SwacoRuntime"]),

        .testTarget(name: "SwacoTests", dependencies: ["Swaco", "SwacoTesting"]),
        .testTarget(name: "SwacoRuntimeTests", dependencies: ["SwacoRuntime", "SwacoTesting"]),
        .testTarget(name: "SwacoInteractionTests",
                    dependencies: ["SwacoInteraction", "SwacoRuntime", "SwacoTesting"]),
        .testTarget(name: "SwacoExtensionsTests",
                    dependencies: ["SwacoExtensions", "SwacoInteraction", "SwacoRuntime", "SwacoTesting"]),
        .testTarget(name: "SwacoAITests", dependencies: ["SwacoAI", "SwacoOpenAI"],
                    resources: [.copy("Fixtures")]),
        .testTarget(name: "SwacoFoundationModelsTests",
                    dependencies: ["SwacoFoundationModels", "SwacoRuntime", "SwacoTesting"]),

        // The canonical first program, built in CI so it never drifts.
        .executableTarget(name: "FirstProgram", dependencies: ["Swaco", "SwacoOpenAI"],
                          path: "Examples/FirstProgram"),

        // Complete, compiling strategies an app copies and owns from then on.
        // Built here so they cannot drift from the API; shipped to nobody.
        .target(name: "Templates", dependencies: ["Swaco"], path: "Examples/Templates",
                exclude: ["README.md"]),
        .testTarget(name: "TemplatesTests",
                    dependencies: ["Templates", "SwacoRuntime", "SwacoTesting"]),
    ]
)
