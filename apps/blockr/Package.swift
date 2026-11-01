// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "BlockrCore", platforms: [.iOS(.v17), .macOS(.v14)], products: [.library(name: "BlockrCore", targets: ["BlockrCore"])], targets: [.target(name: "BlockrCore"), .testTarget(name: "BlockrCoreTests", dependencies: ["BlockrCore"])])
