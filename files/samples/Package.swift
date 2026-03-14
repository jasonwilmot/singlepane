// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Velocity",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "VelocityServer",
            targets: ["VelocityServer"]
        ),
        .executable(
            name: "VelocityIndexer",
            targets: ["VelocityIndexer"]
        ),
        .library(
            name: "VelocityCore",
            targets: ["VelocityCore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
        .package(url: "https://github.com/apple/swift-system.git", from: "1.3.0"),
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.0"),
    ],
    targets: [
        // ── Core Library ───────────────────────────────────
        .target(
            name: "VelocityCore",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "SystemPackage", package: "swift-system"),
                .product(name: "SQLite", package: "SQLite.swift"),
            ],
            path: "Sources/Core",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                .unsafeFlags(["-warnings-as-errors"]),
            ]
        ),

        // ── Services ───────────────────────────────────────
        .target(
            name: "VelocityServices",
            dependencies: ["VelocityCore"],
            path: "Sources/Services"
        ),

        // ── Server (for dev tools / remote browsing) ──────
        .executableTarget(
            name: "VelocityServer",
            dependencies: [
                "VelocityCore",
                "VelocityServices",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/Server"
        ),

        // ── Search Indexer CLI ─────────────────────────────
        .executableTarget(
            name: "VelocityIndexer",
            dependencies: [
                "VelocityCore",
                "VelocityServices",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/Indexer"
        ),

        // ── Tests ──────────────────────────────────────────
        .testTarget(
            name: "VelocityTests",
            dependencies: ["VelocityCore", "VelocityServices"],
            path: "Tests/Unit",
            resources: [
                .copy("Fixtures"),
            ]
        ),
        .testTarget(
            name: "VelocityIntegrationTests",
            dependencies: ["VelocityCore", "VelocityServices"],
            path: "Tests/Integration"
        ),
        .testTarget(
            name: "VelocityPerformanceTests",
            dependencies: ["VelocityCore", "VelocityServices"],
            path: "Tests/Performance"
        ),
    ]
)
