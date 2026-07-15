// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "SyntaxKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SyntaxKit", targets: ["SyntaxKit"]),
    ],
    dependencies: [
        .package(path: "../DocumentCore"),
        .package(url: "https://github.com/ChimeHQ/SwiftTreeSitter", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "SyntaxKit",
            dependencies: ["DocumentCore", "SwiftTreeSitter"]
        ),
        .testTarget(name: "SyntaxKitTests", dependencies: ["SyntaxKit"]),
    ]
)
