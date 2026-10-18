// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShotrCore",
    products: [.library(name: "ShotrCore", targets: ["ShotrCore"])],
    targets: [
        .target(name: "ShotrCore", path: "Shotr/Core"),
        .testTarget(name: "ShotrCoreTests", dependencies: ["ShotrCore"], path: "Tests")
    ]
)
