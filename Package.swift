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
        .library(name: "SwacoConformance", targets: ["SwacoConformance"]),
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

        // Development tools an app links like any other: the replayable mock
        // provider, and recording a real exchange to replay later. No test
        // framework, so a preview and an app can use them.
        .target(name: "SwacoTesting", dependencies: ["Swaco"]),

        // The contracts any implementation runs, and the harness that kills a
        // process after every event. Public, so companions and third parties
        // hold themselves to the same standard. Depends on Swift Testing,
        // which is why it is not the same target as the mock.
        .target(name: "SwacoConformance", dependencies: ["Swaco", "SwacoRuntime"]),

        .testTarget(name: "SwacoTests", dependencies: ["Swaco", "SwacoTesting"]),
        .testTarget(name: "SwacoRuntimeTests",
                    dependencies: ["SwacoRuntime", "SwacoTesting", "SwacoConformance", "SwacoAI"]),
        .testTarget(name: "SwacoInteractionTests",
                    dependencies: ["SwacoInteraction", "SwacoRuntime", "SwacoTesting"]),
        .testTarget(name: "SwacoExtensionsTests",
                    dependencies: ["SwacoExtensions", "SwacoInteraction", "SwacoRuntime",
                                   "SwacoTesting", "SwacoAI"]),
        .testTarget(name: "SwacoAITests", dependencies: ["SwacoAI", "SwacoOpenAI", "SwacoTesting"],
                    resources: [.copy("Fixtures")]),
        .testTarget(name: "SwacoFoundationModelsTests",
                    dependencies: ["SwacoFoundationModels", "SwacoRuntime", "SwacoTesting"]),

        // The canonical first program, built in CI so it never drifts.
        .executableTarget(name: "FirstProgram", dependencies: ["Swaco", "SwacoOpenAI"],
                          path: "Examples/FirstProgram"),

        // Run by hand to refresh a recording against a real model. CI has no
        // key and needs none.
        .executableTarget(name: "Record",
                          dependencies: ["Swaco", "SwacoOpenAI", "SwacoExtensions", "SwacoInteraction",
                                         "SwacoTesting"],
                          path: "Examples/Record"),

        // Complete, compiling strategies an app copies and owns from then on.
        // Built here so they cannot drift from the API; shipped to nobody.
        .target(name: "Templates", dependencies: ["Swaco"], path: "Examples/Templates",
                exclude: ["README.md"]),
        .testTarget(name: "TemplatesTests",
                    dependencies: ["Templates", "SwacoRuntime", "SwacoTesting"]),
    ]
)
