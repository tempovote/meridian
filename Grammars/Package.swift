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
        .library(name: "TreeSitterPython", targets: ["TreeSitterPython"]),
        .library(name: "TreeSitterYaml", targets: ["TreeSitterYaml"]),
        .library(name: "TreeSitterToml", targets: ["TreeSitterToml"]),
        .library(name: "TreeSitterBash", targets: ["TreeSitterBash"]),
        .library(name: "TreeSitterC", targets: ["TreeSitterC"]),
        .library(name: "TreeSitterCpp", targets: ["TreeSitterCpp"]),
        .library(name: "TreeSitterRust", targets: ["TreeSitterRust"]),
        .library(name: "TreeSitterGo", targets: ["TreeSitterGo"]),
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
        .target(
            name: "TreeSitterPython",
            cSettings: [.headerSearchPath(".")],
        ),
        .testTarget(name: "TreeSitterPythonTests", dependencies: ["TreeSitterPython"]),
        .target(
            name: "TreeSitterYaml",
            cSettings: [.headerSearchPath(".")],
        ),
        .testTarget(name: "TreeSitterYamlTests", dependencies: ["TreeSitterYaml"]),
        .target(
            name: "TreeSitterToml",
            cSettings: [.headerSearchPath(".")],
        ),
        .testTarget(name: "TreeSitterTomlTests", dependencies: ["TreeSitterToml"]),
        .target(
            name: "TreeSitterBash",
            cSettings: [.headerSearchPath(".")],
        ),
        .testTarget(name: "TreeSitterBashTests", dependencies: ["TreeSitterBash"]),
        .target(
            name: "TreeSitterC",
            cSettings: [.headerSearchPath(".")],
        ),
        .testTarget(name: "TreeSitterCTests", dependencies: ["TreeSitterC"]),
        .target(
            name: "TreeSitterCpp",
            cSettings: [.headerSearchPath(".")],
        ),
        .testTarget(name: "TreeSitterCppTests", dependencies: ["TreeSitterCpp"]),
        .target(
            name: "TreeSitterRust",
            cSettings: [.headerSearchPath(".")],
        ),
        .testTarget(name: "TreeSitterRustTests", dependencies: ["TreeSitterRust"]),
        .target(
            name: "TreeSitterGo",
            cSettings: [.headerSearchPath(".")],
        ),
        .testTarget(name: "TreeSitterGoTests", dependencies: ["TreeSitterGo"]),
    ],
)
