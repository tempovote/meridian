// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "DocumentCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DocumentCore", targets: ["DocumentCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
    ],
    targets: [
        .target(
            name: "DocumentCore",
            dependencies: [.product(name: "Collections", package: "swift-collections")],
        ),
        .testTarget(name: "DocumentCoreTests", dependencies: ["DocumentCore"]),
        .testTarget(name: "PerformanceTests", dependencies: ["DocumentCore"]),
    ],
)
