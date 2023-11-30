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
        ),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.2.3"),
        .package(url: "https://github.com/jpsim/Yams", exact: "5.0.6"),
        .package(url: "https://github.com/protonjohn/SwiftGit2", exact: "0.10.2"),
        .package(url: "https://github.com/mxcl/Version", exact: "2.0.1"),
        .package(url: "https://github.com/pointfreeco/swift-parsing", exact: "0.13.0"),
        .package(url: "https://github.com/protonjohn/plistutil", exact: "0.1.0-beta.1"),
        .package(url: "https://github.com/apple/swift-docc-plugin", exact: "1.0.0"),
        .package(url: "https://github.com/almazrafi/DictionaryCoder", exact: "1.1.0")
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
                .product(name: "Parsing", package: "swift-parsing"),
            ]
        ),
        .target(
            name: "LHC",
            dependencies: [
                "Version",
                "SwiftGit2",
                "LHCInternal",
                "DictionaryCoder",
                .product(name: "Parsing", package: "swift-parsing")
            ],
            resources: [
                .process("lhcconfig.example")
            ]
        ),
        .target(name: "LHCInternal",
            dependencies: [
                "Version",
                "SwiftGit2",
                "Yams",
                .product(name: "CodingCollection", package: "plistutil"),
                ]
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
