// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "Grammars",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TreeSitterJSON", targets: ["TreeSitterJSON"]),
        .library(name: "TreeSitterSwift", targets: ["TreeSitterSwift"]),
    ],
    targets: [
        .target(
            name: "TreeSitterJSON",
            cSettings: [.headerSearchPath(".")],
        ),
        .testTarget(name: "TreeSitterJSONTests", dependencies: ["TreeSitterJSON"]),
        .target(
            name: "TreeSitterSwift",
            cSettings: [.headerSearchPath(".")],
        ),
        .testTarget(name: "TreeSitterSwiftTests", dependencies: ["TreeSitterSwift"]),
    ],
)
