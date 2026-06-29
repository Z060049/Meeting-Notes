// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AutoScribe",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AutoScribe", targets: ["AutoScribeApp"]),
        .library(name: "AutoScribeCore", targets: ["AutoScribeCore"])
    ],
    targets: [
        .target(
            name: "AutoScribeCore",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("ScreenCaptureKit")
            ]
        ),
        .executableTarget(
            name: "AutoScribeApp",
            dependencies: ["AutoScribeCore"]
        ),
        .testTarget(
            name: "AutoScribeCoreTests",
            dependencies: ["AutoScribeCore"]
        )
    ]
)
