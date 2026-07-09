// swift-tools-version: 5.10

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
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-examples", branch: "main"),
    ],
    targets: [
        .target(
            name: "AutoScribeCore",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "MLXLLM", package: "mlx-swift-examples"),
                .product(name: "MLXLMCommon", package: "mlx-swift-examples"),
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("ScreenCaptureKit"),
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
