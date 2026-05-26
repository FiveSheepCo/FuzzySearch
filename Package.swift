// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FuzzySearch",
    platforms: [
        .macOS(.v13),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "FuzzySearch",
            targets: ["FuzzySearch"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/ordo-one/benchmark", .upToNextMajor(from: "1.4.0")),
        .package(url: "https://github.com/ukushu/Ifrit", .upToNextMajor(from: "4.0.0")),
        .package(url: "https://github.com/krisk/fuse-swift.git", exact: Version("2.0.0-rc.1")),
    ],
    targets: [
        .target(
            name: "FuzzySearch"
        ),
        .testTarget(
            name: "FuzzySearchTests",
            dependencies: ["FuzzySearch"]
        ),
        .executableTarget(
            name: "QualityEval",
            dependencies: [
                .product(name: "Ifrit", package: "Ifrit"),
                .product(name: "Fuse", package: "fuse-swift"),
                .targetItem(name: "FuzzySearch", condition: .none),
            ],
            path: "Tools/QualityEval"
        ),
    ],
    swiftLanguageModes: [.v6]
)

// Benchmark of IfritBench
package.targets += [
    .executableTarget(
        name: "CompetitorBench",
        dependencies: [
            .product(name: "Benchmark", package: "benchmark"),
            .product(name: "Ifrit", package: "Ifrit"),
            .product(name: "Fuse", package: "fuse-swift"),
            .targetItem(name: "FuzzySearch", condition: .none),
        ],
        path: "Benchmarks/CompetitorBench",
        plugins: [
            .plugin(name: "BenchmarkPlugin", package: "benchmark")
        ]
    ),
]
