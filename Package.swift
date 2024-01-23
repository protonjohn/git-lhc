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
        .package(url: "https://github.com/protonjohn/SwiftGit2", revision: "a7c723c68cd8557e8ee71ff4944a8940249656ab"),
        .package(url: "https://github.com/mxcl/Version", exact: "2.0.1"),
        .package(url: "https://github.com/pointfreeco/swift-parsing", exact: "0.13.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin", exact: "1.0.0"),
        .package(url: "https://github.com/almazrafi/DictionaryCoder", exact: "1.1.0"),
        .package(url: "https://github.com/stencilproject/Stencil", exact: "0.15.1"),
        .package(url: "https://github.com/apple/swift-markdown", exact: "0.3.0"),
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
                .product(name: "Parsing", package: "swift-parsing")
            ],
            resources: [
                .process("lhc.example"),
                .process("Templates")
            ]
        ),
        .target(name: "LHCInternal",
            dependencies: [
                "Version",
                "SwiftGit2",
                "Yams",
                "LHCInternalC"
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
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        )
    ]
)
