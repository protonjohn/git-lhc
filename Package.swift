// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-gluon",
    platforms: [.macOS(.v13)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .plugin(
            name: "EmbedChangelog",
            targets: ["EmbedChangelog"]
        ),
        .plugin(
            name: "EmbedVersion",
            targets: ["EmbedVersion"]
        ),
        .executable(
            name: "gluon",
            targets: ["gluon"]
        ),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.2.3"),
        .package(url: "https://github.com/jpsim/Yams", exact: "5.0.6"),
        .package(url: "https://github.com/protonjohn/SwiftGit2", exact: "0.10.1"),
        .package(url: "https://github.com/mxcl/Version", exact: "2.0.1"),
        .package(url: "https://github.com/pointfreeco/swift-parsing", exact: "0.13.0"),
    ],
    targets: [
        .executableTarget(
            name: "gluon",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "Yams",
                "SwiftGit2",
                "Version",
                .product(name: "Parsing", package: "swift-parsing"),
            ]
        ),
        .plugin(
            name: "EmbedChangelog",
            capability: .buildTool(),
            dependencies: [
                "gluon"
            ]
        ),
        .plugin(
            name: "EmbedVersion",
            capability: .buildTool(),
            dependencies: [
                "gluon"
            ]
        ),
        .testTarget(
            name: "GluonTests",
            dependencies: [
                "gluon",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        )
    ]
)
