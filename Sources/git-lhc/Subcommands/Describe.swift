//
//  DescribeRelease.swift
//  
//
//  Created by John Biggs on 11.10.23.
//

import Foundation
import ArgumentParser
import SwiftGit2
import Version
import LHC
import LHCInternal

struct Describe: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Display the changelog for the specified version(s)."
    )

    @OptionGroup()
    var parent: LHC.Options

    @Flag(
        name: .shortAndLong,
        help: """
            Show the changelog up to HEAD since the last release tag, as if a new release were being created. \
            Note: This flag is sensitive to the --channel option.
            """
    )
    var dryRun: Bool = false

    @Option(
        name: .shortAndLong,
        help: "Which parts of the changelog to show. Can be latest, all, or a specific commit hash."
    )
    var show: OutputSpec = .latest

    @Option(
        name: .shortAndLong,
        help: "The output format to use. Possible values are \(ReleaseFormat.possibleValues)."
    )
    var format: ReleaseFormat = .text

    @Option(
        name: .shortAndLong,
        help: "An optional path to an output file. If unspecified, defaults to stdout.",
        transform: URL.createFromPathOrThrow(_:)
    )
    var output: URL?

    @Flag(help: "Whether to include project IDs in release descriptions.")
    var redactProjectIds: Bool = false

    @Flag(help: "Whether to include commit hashes in release descriptions.")
    var redactCommitHashes: Bool = false

    mutating func run() throws {
        Internal.initialize()

        let repo = try Internal.openRepo(at: parent.repo)

        let releases: [Release]
        switch show {
        case .all:
            releases = try repo.allReleases(
                allowDirty: dryRun,
                untaggedReleaseChannel: parent.channel,
                forceLatestVersionTo: nil,
                options: parent.options
            )
        case .latest:
            guard let release = try repo.latestRelease(
                allowDirty: dryRun,
                untaggedReleaseChannel: parent.channel,
                forceLatestVersionTo: nil,
                options: parent.options
            ) else {
                releases = []
                break
            }

            releases = [release]
        case let .exact(version):
            guard let release = try repo.release(exactVersion: version, options: parent.options) else {
                throw DescribeReleaseError.versionNotFound(version: version, train: parent.train)
            }

            releases = [release]
        }

        try show(releases: releases)
    }
    
    mutating func show(releases: [Release]) throws {
        let result = try parent.show(
            releases: releases,
            format: format,
            includeCommitHashes: !redactCommitHashes,
            includeProjectIds: !redactProjectIds
        )

        if let outputPath = output?.path(), let data = result.data {
            guard Internal.fileManager
                .createFile(atPath: outputPath, contents: data) else {
                throw LHCError.invalidPath(outputPath)
            }
        } else if let string = result.string {
            Internal.print(string)
        }
    }
}

enum OutputSpec: ExpressibleByArgument {
    case all
    case latest
    case exact(version: Version)

    init?(argument: String) {
        switch argument {
        case "all":
            self = .all
        case "latest":
            self = .latest
        default:
            guard let version = Version(argument) else {
                return nil
            }
            self = .exact(version: version)
        }
    }
}

enum DescribeReleaseError: Error, CustomStringConvertible {
    case emptyRelease(from: TagReferenceish, to: ObjectID)
    case versionNotFound(version: Version, train: String?)

    var description: String {
        switch self {
        case let .emptyRelease(tag, leaf):
            return "Not creating new release: no commits exist from tag '\(tag.name)' to commit '\(leaf)'"
        case let .versionNotFound(version, train):
            var result = "No version \(version) found in commit history"
            if let releaseTrain = train {
                result += " for train '\(train ?? "(nil)")'"
            }
            return result
        }
    }
}
