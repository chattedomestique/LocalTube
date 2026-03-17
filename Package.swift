// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LocalTube",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "LocalTube",
            path: "Sources/LocalTube",
            resources: [
                .copy("Resources"),
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        )
    ]
)
