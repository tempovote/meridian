// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "ThemeKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ThemeKit", targets: ["ThemeKit"]),
    ],
    targets: [
        .target(
            name: "ThemeKit",
            resources: [.copy("Resources")],
        ),
        .testTarget(name: "ThemeKitTests", dependencies: ["ThemeKit"]),
    ],
)
