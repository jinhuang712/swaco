// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swaco",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "Swaco", targets: ["Swaco"]),
    ],
    targets: [
        .target(name: "Swaco"),
        .testTarget(name: "SwacoTests", dependencies: ["Swaco"]),
    ]
)
