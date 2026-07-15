// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "SearchKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SearchKit", targets: ["SearchKit"]),
    ],
    dependencies: [
        .package(path: "../DocumentCore"),
    ],
    targets: [
        .target(name: "SearchKit", dependencies: ["DocumentCore"]),
        .testTarget(name: "SearchKitTests", dependencies: ["SearchKit"]),
    ]
)
