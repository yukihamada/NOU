// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NOU",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMinor(from: "2.30.3")),
        .package(url: "https://github.com/hummingbird-project/hummingbird", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "NOU",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Hummingbird", package: "hummingbird"),
            ],
            path: "Sources",
            resources: []
        ),
    ]
)
