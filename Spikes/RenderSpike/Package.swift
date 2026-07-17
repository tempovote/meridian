// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "RenderSpike",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../../Packages/DocumentCore"),
    ],
    targets: [
        .executableTarget(
            name: "renderspike",
            dependencies: [.product(name: "DocumentCore", package: "DocumentCore")],
            path: "Sources/RenderSpike",
        ),
        .testTarget(
            name: "RenderSpikeTests",
            dependencies: ["renderspike"],
            path: "Tests/RenderSpikeTests",
        ),
    ],
)
