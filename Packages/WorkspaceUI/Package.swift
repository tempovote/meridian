// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "WorkspaceUI",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "WorkspaceUI", targets: ["WorkspaceUI"]),
    ],
    dependencies: [
        .package(path: "../EditorUI"),
        .package(path: "../SettingsKit"),
    ],
    targets: [
        .target(name: "WorkspaceUI", dependencies: ["EditorUI", "SettingsKit"]),
        .testTarget(name: "WorkspaceUITests", dependencies: ["WorkspaceUI"]),
    ]
)
