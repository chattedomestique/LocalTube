// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocalTube",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "LocalTube",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/LocalTube",
            resources: [
                .copy("Resources"),
            ],
            swiftSettings: [
                // Staying on v5 for now: enabling .v6 surfaces ~90 strict-
                // concurrency errors (nonisolated global state in AppLogger,
                // PINService, formatters; mutable buffer capture in
                // ShellRunner). Tracked as a focused follow-up so the bulk
                // improvements in this branch ship as a working build.
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        )
    ]
)
