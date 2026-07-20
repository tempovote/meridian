// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "Grammars",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TreeSitterJSON", targets: ["TreeSitterJSON"]),
        .library(name: "TreeSitterSwift", targets: ["TreeSitterSwift"]),
        .library(name: "TreeSitterJavascript", targets: ["TreeSitterJavascript"]),
        .library(name: "TreeSitterTypescript", targets: ["TreeSitterTypescript"]),
        .library(name: "TreeSitterHtml", targets: ["TreeSitterHtml"]),
        .library(name: "TreeSitterCss", targets: ["TreeSitterCss"]),
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
        .target(
            name: "TreeSitterJavascript",
            cSettings: [.headerSearchPath(".")],
        ),
        .testTarget(name: "TreeSitterJavascriptTests", dependencies: ["TreeSitterJavascript"]),
        .target(
            name: "TreeSitterTypescript",
            cSettings: [.headerSearchPath(".")],
        ),
        .testTarget(name: "TreeSitterTypescriptTests", dependencies: ["TreeSitterTypescript"]),
        .target(
            name: "TreeSitterHtml",
            cSettings: [.headerSearchPath(".")],
        ),
        .testTarget(name: "TreeSitterHtmlTests", dependencies: ["TreeSitterHtml"]),
        .target(
            name: "TreeSitterCss",
            cSettings: [.headerSearchPath(".")],
        ),
        .testTarget(name: "TreeSitterCssTests", dependencies: ["TreeSitterCss"]),
    ],
)
