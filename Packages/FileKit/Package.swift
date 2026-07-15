// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "FileKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FileKit", targets: ["FileKit"]),
    ],
    dependencies: [
        .package(path: "../DocumentCore"),
    ],
    targets: [
        .target(name: "FileKit", dependencies: ["DocumentCore"]),
        .testTarget(name: "FileKitTests", dependencies: ["FileKit"]),
    ],
)
