// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "git-lhc",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LHC", targets: ["LHC"]),
        .executable(
            name: "git-lhc",
            targets: ["git-lhc"]
        )
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.2.3"),
        .package(url: "https://github.com/jpsim/Yams", exact: "5.0.6"),
        .package(url: "https://github.com/protonjohn/SwiftGit2", exact: "0.12.0"),
        .package(url: "https://github.com/mxcl/Version", exact: "2.1.0"),
        .package(url: "https://github.com/pointfreeco/swift-parsing", exact: "0.13.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin", exact: "1.0.0"),
        .package(url: "https://github.com/almazrafi/DictionaryCoder", exact: "1.1.0"),
        .package(url: "https://github.com/stencilproject/Stencil", exact: "0.15.1"),
        .package(url: "https://github.com/apple/swift-markdown", exact: "0.3.0"),
        .package(url: "https://github.com/apple/pkl-swift", from: "0.2.1"),
    ],
    targets: [
        .executableTarget(
            name: "git-lhc",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "Yams",
                "SwiftGit2",
                "Version",
                "LHC",
                "LHCInternal",
                "Stencil",
                .product(name: "Parsing", package: "swift-parsing"),
            ]
        ),
        .target(
            name: "LHC",
            dependencies: [
                "Version",
                "Stencil",
                "SwiftGit2",
                "LHCInternal",
                "DictionaryCoder",
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Parsing", package: "swift-parsing"),
                .product(name: "PklSwift", package: "pkl-swift"),
            ],
            resources: [
                .process("Templates"),
            ]
        ),
        .target(name: "LHCInternal",
            dependencies: [
                "Version",
                "SwiftGit2",
                "Yams",
                "LHCInternalC",
                .product(name: "PklSwift", package: "pkl-swift"),
            ],
            resources: [
                .process("Trains.pkl"),
            ]
        ),
        .target(
            name: "LHCInternalC",
            dependencies: []
        ),
        .testTarget(
            name: "LHCTests",
            dependencies: [
                "git-lhc",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "PklSwift", package: "pkl-swift"),
            ]
        )
    ]
)
