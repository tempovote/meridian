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
        .package(path: "../../Grammars"),
        .package(url: "https://github.com/ChimeHQ/SwiftTreeSitter", from: "0.9.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter", .upToNextMinor(from: "0.25.0")),
    ],
    targets: [
        .target(
            name: "SyntaxKit",
            dependencies: [
                "DocumentCore",
                "SwiftTreeSitter",
                .product(name: "TreeSitter", package: "tree-sitter"),
                .product(name: "TreeSitterJSON", package: "Grammars"),
                .product(name: "TreeSitterSwift", package: "Grammars"),
            ],
        ),
        .testTarget(name: "SyntaxKitTests", dependencies: ["SyntaxKit"]),
    ],
)
