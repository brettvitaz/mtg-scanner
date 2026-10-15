// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "MTGScannerKit",
    platforms: [
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "MTGScannerKit",
            targets: ["MTGScannerKit"]
        ),
        .library(
            name: "MTGScannerFixtures",
            targets: ["MTGScannerFixtures"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/nalexn/ViewInspector", exact: "0.10.5")
    ],
    targets: [
        .target(
            name: "MTGScannerKit",
            path: "Sources/MTGScannerKit",
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "MTGScannerFixtures",
            dependencies: ["MTGScannerKit"],
            path: "Sources/MTGScannerFixtures",
            resources: [
                .process("Resources/FixtureFrames")
            ]
        ),
        .testTarget(
            name: "MTGScannerKitTests",
            dependencies: [
                "MTGScannerKit", "MTGScannerFixtures",
                .product(name: "ViewInspector", package: "ViewInspector")
            ],
            path: "Tests/MTGScannerKitTests",
            resources: [
                .process("CropEvaluationFixtures")
            ]
        )
    ]
)
