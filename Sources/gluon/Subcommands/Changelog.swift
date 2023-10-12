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
import Yams

struct Changelog: ParsableCommand {
    private typealias TaggedRelease = (tag: TagReferenceish, version: Version)
    private typealias ReleaseRange = (last: TaggedRelease?, release: ReferenceType)

    @OptionGroup()
    var parent: Gluon.Options

    @Option()
    var show: OutputSpec = .latest

    @Option()
    var format: ChangelogFormat = .text

    @Option(transform: Configuration.train(named:))
    var train: Configuration.Train?

    @Option(name: .shortAndLong, transform: URL.createFromPathOrThrow(_:))
    var output: URL?

    func run() throws {
        SwiftGit2.initialize()

        let repo = try Gluon.openRepo(at: parent.repo)
        let ranges = try findRanges(in: repo, for: train)
        let releases = try releases(in: repo, fromCommitRanges: ranges)

        try show(releases: releases)
    }

    private func releases(
        in repo: Repositoryish,
        fromCommitRanges ranges: [(
            last: TaggedRelease?,
            release: ReferenceType
        )]
    ) throws -> [Release] {
        try ranges.reduce(into: []) {
            let repoCommits = try repo.commits(from: $1.release.oid, since: $1.last?.tag.oid)
            let commits = repoCommits.compactMap {
                do {
                    // Attempt to properly parse a conventional commit. If we can't, then fake one using the
                    // commit subject and body.
                    return try ConventionalCommit(message: $0.message)
                } catch {
                    Gluon.print(error, to: &FileHandle.stderr)
                    return nil
                }
            }

            var body: String?
            if let tagReference = $1.release as? TagReferenceish,
               let message = tagReference.message {
                if let conventionalTag = try? ConventionalCommit(message: message) {
                    // Annotated tags formatted like conventional commits look like:
                    // release(<train name>): Version 3.0.1
                    //
                    // <body follows>
                    //
                    // <trailers follow optionally>
                    //
                    // To avoid duplicating information, we'll only put the body here if the commit parses correctly.
                    body = conventionalTag.body
                } else {
                    body = message
                }
            }

            var tagged = false
            let version: Version
            if let releaseTag = $1.release as? TagReferenceish,
               let taggedVersion = Version(
                   prefix: train?.tagPrefix,
                   versionString: releaseTag.name
               )
            {
                version = taggedVersion
                tagged = true
            } else if let last = $1.last {
                version = commits.nextVersion(after: last.version)
            } else {
                version = Version(major: 0, minor: 0, patch: 1)
            }

            $0.append(.init(
                version: version,
                tagged: tagged,
                train: train,
                body: body,
                conventionalCommits: commits,
                correspondingHashes: repoCommits.map(\.oid)
            ))
        }
    }

    private func lastReachableTag(
        in repo: Repositoryish,
        among references: ArraySlice<TaggedRelease>,
        from: ObjectID,
        inclusive: Bool = false,
        prerelease: Bool = false
    ) throws -> TaggedRelease? {
        try references.last {
            try (inclusive || $0.tag.oid != from) &&
                (prerelease || !$0.version.isPrerelease) &&
                repo.isReachable($0.tag.oid, from: from)
        }
    }

    private func findRanges(
        in repo: Repositoryish,
        for train: Configuration.Train?
    ) throws -> [ReleaseRange] {
        let taggedReleases = try repo.allTags().compactMap { (tag: TagReferenceish) -> TaggedRelease? in
            guard let version = Version(
                prefix: train?.tagPrefix,
                versionString: tag.name
            ) else { return nil }

            return (tag: tag, version: version)
        }.sorted { $0.version < $1.version }

        switch show {
        case .all:
            return try allReleaseRanges(
                in: repo,
                for: train,
                taggedReleases: taggedReleases
            )
        case .latest:
            return try [latestReleaseRange(
                in: repo,
                for: train,
                taggedReleases: taggedReleases
            )]
        case let .exact(version):
            return try [releaseRange(
                in: repo,
                for: train,
                exactVersion: version,
                taggedReleases: taggedReleases
            )]
        }
    }

    private func releaseRange(in repo: Repositoryish, for train: Configuration.Train?, exactVersion version: Version, taggedReleases: [TaggedRelease]) throws -> ReleaseRange {
        let index = taggedReleases.binarySearch { $0.version < version }

        guard 0 <= index && index < taggedReleases.count else {
            throw ChangelogError.versionNotFound(version: version, train: train)
        }

        let releaseTag = taggedReleases[index]
        guard releaseTag.version == version else {
            throw ChangelogError.versionNotFound(version: version, train: train)
        }

        let lastVersion = try lastReachableTag(
            in: repo,
            among: taggedReleases[0..<index],
            from: releaseTag.tag.oid,
            prerelease: false
        )

        return (lastVersion, releaseTag.tag)
    }

    private func latestReleaseRange(in repo: Repositoryish, for train: Configuration.Train?, taggedReleases: [TaggedRelease]) throws -> ReleaseRange {
        let head: ReferenceType = try repo.currentBranch() ?? repo.HEAD()

        let lastVersion = try lastReachableTag(
            in: repo,
            among: taggedReleases[...],
            from: head.oid
        )

        if !(head is TagReferenceish) {
            // Do a reverse lookup to see if the current version is actually HEAD.
            // This lets us make sure we set the "tagged" property correctly on the Release object.
            let maybeThisVersion = try lastReachableTag(
                in: repo,
                among: taggedReleases[...],
                from: head.oid,
                inclusive: true
            )

            if let thisVersion = maybeThisVersion, thisVersion.tag.oid == head.oid {
                return (lastVersion, thisVersion.tag)
            }
        }

        return (lastVersion, head)
    }

    private func allReleaseRanges(in repo: Repositoryish, for train: Configuration.Train?, taggedReleases: [TaggedRelease]) throws -> [ReleaseRange] {
        let head: ReferenceType = try repo.currentBranch() ?? repo.HEAD()

        var ranges: [ReleaseRange] = try taggedReleases
            .filter { !$0.version.isPrerelease }
            .enumerated()
            .reduce(into: []) { result, element in
                let (i, (tag, _)) = element
                let lastVersion = try lastReachableTag(
                    in: repo,
                    among: taggedReleases[0..<i],
                    from: tag.oid
                )
                result.append((lastVersion, tag))
            }

        if let last = ranges.last, last.release.oid != head.oid {
            let lastUntaggedVersion = try lastReachableTag(
                in: repo,
                among: taggedReleases[...],
                from: head.oid
            )
            ranges.append((lastUntaggedVersion, head))
        }

        // We want the most recent versions first.
        return ranges.reversed()
    }

    func show(releases: [Release]) throws {
        let result: StringOrData

        switch format {
        case .json:
            let encoder = JSONEncoder()
            result = try .init(encoder.encode(releases))
        case .yaml:
            let encoder = YAMLEncoder()
            result = try .init(encoder.encode(releases))
        case .plist:
            let encoder = PropertyListEncoder()
            result = try .init(encoder.encode(releases))
        case .versions:
            let versions = releases.map(\.versionString).joined(separator: ",")
            result = .init(versions)
        case .text:
            let description = releases.map(\.description).joined(separator: "\n")
            result = .init(description)
        }

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

enum ChangelogFormat: String, ExpressibleByArgument {
    case text
    case json
    case yaml
    case plist
    case versions
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
