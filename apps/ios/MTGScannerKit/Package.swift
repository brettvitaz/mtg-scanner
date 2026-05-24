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
            dependencies: ["MTGScannerKit", "MTGScannerFixtures"],
            path: "Tests/MTGScannerKitTests"
        )
    ]
)
