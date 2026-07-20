// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "Grammars",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TreeSitterJSON", targets: ["TreeSitterJSON"]),
    ],
    targets: [
        .target(
            name: "TreeSitterJSON",
            cSettings: [.headerSearchPath(".")],
        ),
        .testTarget(name: "TreeSitterJSONTests", dependencies: ["TreeSitterJSON"]),
    ],
)
