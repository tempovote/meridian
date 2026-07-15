// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "PluginHost",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PluginHost", targets: ["PluginHost"]),
    ],
    dependencies: [
        .package(path: "../PluginAPI"),
    ],
    targets: [
        .target(name: "PluginHost", dependencies: ["PluginAPI"]),
        .testTarget(name: "PluginHostTests", dependencies: ["PluginHost"]),
    ],
)
