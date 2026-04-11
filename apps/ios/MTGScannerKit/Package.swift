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
        )
    ],
    targets: [
        .target(
            name: "MTGScannerKit",
            path: "Sources/MTGScannerKit",
            resources: [
                .process("Resources/FixtureFrames")
            ]
        ),
        .testTarget(
            name: "MTGScannerKitTests",
            dependencies: ["MTGScannerKit"],
            path: "Tests/MTGScannerKitTests"
        )
    ]
)
