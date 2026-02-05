// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "slog",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/onevcat/Rainbow.git", from: "4.0.0"),
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", branch: "main"),
        .package(url: "https://github.com/toon-format/toon-swift.git", from: "0.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "slog",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Rainbow", package: "Rainbow"),
                .product(name: "Subprocess", package: "swift-subprocess"),
                .product(name: "ToonFormat", package: "toon-swift"),
            ]
        ),
        .testTarget(
            name: "slogTests",
            dependencies: ["slog"]
        ),
    ]
)
