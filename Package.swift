// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShotsCore",
    products: [.library(name: "ShotsCore", targets: ["ShotsCore"])],
    targets: [
        .target(name: "ShotsCore", path: "Shots/Core"),
        .testTarget(name: "ShotsCoreTests", dependencies: ["ShotsCore"], path: "Tests")
    ]
)
