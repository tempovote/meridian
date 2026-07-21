// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "EditorUI",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "EditorUI", targets: ["EditorUI"]),
    ],
    dependencies: [
        .package(path: "../DocumentCore"),
        .package(path: "../SettingsKit"),
        .package(path: "../SyntaxKit"),
        .package(path: "../ThemeKit"),
    ],
    targets: [
        .target(
            name: "EditorUI",
            dependencies: ["DocumentCore", "SettingsKit", "SyntaxKit", "ThemeKit"],
        ),
        .testTarget(name: "EditorUITests", dependencies: ["EditorUI", "SettingsKit"]),
    ],
)
