// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Swiftea",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(
            name: "Swiftea",
            targets: ["Swiftea"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.9.1")
    ],
    targets: [
        .executableTarget(
            name: "Swiftea",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Swiftea"
        ),
        .testTarget(
            name: "SwifteaTests",
            dependencies: ["Swiftea"],
            path: "Tests/SwifteaTests"
        )
    ]
)
