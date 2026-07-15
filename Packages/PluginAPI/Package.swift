// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "PluginAPI",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PluginAPI", targets: ["PluginAPI"]),
    ],
    targets: [
        .target(name: "PluginAPI"),
        .testTarget(name: "PluginAPITests", dependencies: ["PluginAPI"]),
    ]
)
