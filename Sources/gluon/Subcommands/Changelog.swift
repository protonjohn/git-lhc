//
//  Changelog.swift
//  
//
//  Created by John Biggs on 11.10.23.
//

import Foundation
import ArgumentParser
import SwiftGit2
import Version

struct Changelog: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Display the changelog for the specified version(s)."
    )

    @OptionGroup()
    var parent: Gluon.Options

    @Option(
        name: .shortAndLong,
        help: "Show the latest changelog entries for the given release channel."
    )
    var channel: ReleaseChannel = .production

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
        help: "Which train to show changes for. Defaults to none.",
        transform: Configuration.train(named:)
    )
    var train: Configuration.Train? = .environment

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

    func run() throws {
        SwiftGit2.initialize()

        let repo = try Gluon.openRepo(at: parent.repo)
        let prereleaseChannel = channel.isPrerelease ? channel.rawValue : nil
        
        let releases: [Release]
        switch show {
        case .all:
            releases = try repo.allReleases(
                for: train,
                allowDirty: dryRun,
                untaggedPrereleaseChannel: prereleaseChannel,
                forceLatestVersionTo: nil
            )
        case .latest:
            guard let release = try repo.latestRelease(
                for: train,
                allowDirty: dryRun,
                untaggedPrereleaseChannel: prereleaseChannel,
                forceLatestVersionTo: nil
            ) else {
                releases = []
                break
            }

            releases = [release]
        case let .exact(version):
            guard let release = try repo.release(for: train, exactVersion: version) else {
                throw ChangelogError.versionNotFound(version: version, train: train)
            }

            releases = [release]
        }

        try show(releases: releases)
    }
    
    func show(releases: [Release]) throws {
        let result = try releases.show(
            format,
            includeCommitHashes: !redactCommitHashes,
            includeProjectIds: !redactProjectIds
        )

        if let outputPath = output?.path(), let data = result.data {
            guard Gluon.fileManager
                .createFile(atPath: outputPath, contents: data) else {
                throw GluonError.invalidPath(outputPath)
            }
        } else if let string = result.string {
            Gluon.print(string)
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

enum ChangelogError: Error, CustomStringConvertible {
    case emptyRelease(from: TagReferenceish, to: ObjectID)
    case versionNotFound(version: Version, train: Configuration.Train?)

    var description: String {
        switch self {
        case let .emptyRelease(tag, leaf):
            return "Not creating new release: no commits exist from tag '\(tag.name)' to commit '\(leaf)'"
        case let .versionNotFound(version, train):
            var result = "No version \(version) found in commit history"
            if let releaseTrain = train {
                result += " for train '\(releaseTrain.name)'"
            }
            return result
        }
    }
}
