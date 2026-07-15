// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "ThemeKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ThemeKit", targets: ["ThemeKit"]),
    ],
    targets: [
        .target(name: "ThemeKit"),
        .testTarget(name: "ThemeKitTests", dependencies: ["ThemeKit"]),
    ],
)
