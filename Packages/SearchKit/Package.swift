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
        .package(path: "../FileKit"),
    ],
    targets: [
        .target(name: "SearchKit", dependencies: ["DocumentCore", "FileKit"]),
        .testTarget(name: "SearchKitTests", dependencies: ["SearchKit"]),
    ],
)
