// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swaco",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "SwacoCore", targets: ["SwacoCore"]),
        .library(name: "SwacoAI", targets: ["SwacoAI"]),
        .library(name: "SwacoOpenAI", targets: ["SwacoOpenAI"]),
        .library(name: "SwacoAnthropic", targets: ["SwacoAnthropic"]),
        .library(name: "SwacoFoundationModels", targets: ["SwacoFoundationModels"]),
        .library(name: "SwacoExtensions", targets: ["SwacoExtensions"]),
        .library(name: "SwacoInteraction", targets: ["SwacoInteraction"]),
        .library(name: "SwacoRuntime", targets: ["SwacoRuntime"]),
        .library(name: "SwacoEnvironment", targets: ["SwacoEnvironment"]),
        .library(name: "SwacoTesting", targets: ["SwacoTesting"]),
        .library(name: "SwacoConformance", targets: ["SwacoConformance"]),
    ],
    targets: [
        .target(name: "SwacoCore", resources: [.copy("PrivacyInfo.xcprivacy")]),

        // The AI layer: shared machinery, then one thin target per vendor.
        .target(name: "SwacoAI", dependencies: ["SwacoCore"], path: "Sources/SwacoAI/Core",
                resources: [.copy("PrivacyInfo.xcprivacy")]),
        .target(name: "SwacoOpenAI", dependencies: ["SwacoAI"], path: "Sources/SwacoAI/OpenAI"),
        .target(name: "SwacoAnthropic", dependencies: ["SwacoAI"], path: "Sources/SwacoAI/Anthropic"),
        .target(name: "SwacoFoundationModels", dependencies: ["SwacoCore"],
                path: "Sources/SwacoAI/FoundationModels"),

        .target(name: "SwacoExtensions", dependencies: ["SwacoCore"], resources: [.copy("PrivacyInfo.xcprivacy")]),
        .target(name: "SwacoInteraction", dependencies: ["SwacoCore"], resources: [.copy("PrivacyInfo.xcprivacy")]),
        .target(name: "SwacoRuntime", dependencies: ["SwacoCore"], resources: [.copy("PrivacyInfo.xcprivacy")]),

        // Where the agent lives: the open vocabulary of sources and the
        // platform facts an app fills in. Depends on the core only; the
        // runtime is a peer, not a dependency, so linking this never drags
        // durability along.
        .target(name: "SwacoEnvironment", dependencies: ["SwacoCore"]),

        // Development tools an app links like any other: the replayable mock
        // provider, and recording a real exchange to replay later. No test
        // framework, so a preview and an app can use them.
        .target(name: "SwacoTesting", dependencies: ["SwacoCore"]),

        // The contracts any implementation runs, and the harness that kills a
        // process after every event. Public, so companions and third parties
        // hold themselves to the same standard. Depends on Swift Testing,
        // which is why it is not the same target as the mock.
        .target(name: "SwacoConformance", dependencies: ["SwacoCore", "SwacoRuntime"]),

        .testTarget(name: "SwacoTests", dependencies: ["SwacoCore", "SwacoTesting"]),
        .testTarget(name: "SwacoRuntimeTests",
                    dependencies: ["SwacoRuntime", "SwacoTesting", "SwacoConformance", "SwacoAI",
                                   "SwacoEnvironment"]),
        .testTarget(name: "SwacoInteractionTests",
                    dependencies: ["SwacoInteraction", "SwacoRuntime", "SwacoTesting"]),
        .testTarget(name: "SwacoExtensionsTests",
                    dependencies: ["SwacoExtensions", "SwacoInteraction", "SwacoRuntime",
                                   "SwacoTesting", "SwacoAI"]),
        .testTarget(name: "SwacoAITests",
                    dependencies: ["SwacoAI", "SwacoOpenAI", "SwacoAnthropic", "SwacoTesting"],
                    resources: [.copy("Fixtures")]),
        .testTarget(name: "SwacoFoundationModelsTests",
                    dependencies: ["SwacoFoundationModels", "SwacoRuntime", "SwacoTesting"]),
        .testTarget(name: "SwacoEnvironmentTests",
                    dependencies: ["SwacoEnvironment", "SwacoCore"]),

        // The canonical first program, built in CI so it never drifts.
        .executableTarget(name: "FirstProgram", dependencies: ["SwacoCore", "SwacoOpenAI"],
                          path: "Examples/FirstProgram"),

        // Run by hand to refresh a recording against a real model. CI has no
        // key and needs none.
        .executableTarget(name: "Record",
                          dependencies: ["SwacoCore", "SwacoOpenAI", "SwacoAnthropic", "SwacoExtensions",
                                         "SwacoInteraction", "SwacoTesting"],
                          path: "Examples/Record"),

        // Complete, compiling strategies an app copies and owns from then on.
        // Built here so they cannot drift from the API; shipped to nobody.
        .executableTarget(name: "Try", dependencies: ["SwacoCore", "SwacoOpenAI", "SwacoAnthropic", "SwacoExtensions"],
                          path: "Examples/Try"),

        .target(name: "Templates", dependencies: ["SwacoCore"], path: "Examples/Templates",
                exclude: ["README.md"]),
        .testTarget(name: "TemplatesTests",
                    dependencies: ["Templates", "SwacoRuntime", "SwacoTesting"]),
    ]
)
