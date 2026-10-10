// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FestrCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "FestrCore", targets: ["FestrCore"])],
    targets: [
        .target(name: "FestrCore", path: "Festr/Core"),
        .testTarget(name: "FestrCoreTests", dependencies: ["FestrCore"], path: "Tests")
    ]
)
