//
//  Release.swift
//
//  Created by John Biggs on 11.10.23.
//

import Foundation
import Version
import SwiftGit2
import ArgumentParser
import Yams

struct Release {
    typealias Category = String

    let versionString: String
    let train: Configuration.Train?
    let tagged: Bool
    let changes: [Category: [Change]]

    let body: String?

    var version: Version? {
        Version(versionString)
    }

    var shortVersion: Version? {
        guard let version else { return nil }
        return Version(version.major, version.minor, version.patch)
    }

    var channel: ReleaseChannel {
        for identifier in version?.prereleaseIdentifiers ?? [] {
            if let channel = ReleaseChannel(rawValue: identifier) {
                return channel
            }
        }

        return .production
    }

    struct Change: Codable {
        let summary: String
        let body: String?
        let commitHash: String
        let projectIds: [String]
    }
}

enum ReleaseChannel: String, CaseIterable, Codable, ExpressibleByArgument {
    case alpha
    case beta
    case releaseCandidate = "rc"
    case production

    static var prereleaseChannels: [Self] = [.alpha, .beta, .releaseCandidate]

    var isPrerelease: Bool {
        Self.prereleaseChannels.contains(self)
    }
}

enum ReleaseFormat: String, CaseIterable, ExpressibleByArgument {
    case text
    case json
    case yaml
    case plist
    case version
}

// Needed in order to include the release channel in the outputted JSON data
extension Release: Codable {
    enum CodingKeys: String, CodingKey {
        case versionString = "version"
        case shortVersion
        case train
        case tagged
        case changes
        case body
        case channel
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.versionString, forKey: .versionString)
        try container.encodeIfPresent(self.shortVersion?.description, forKey: .shortVersion)
        try container.encodeIfPresent(self.train, forKey: .train)
        try container.encode(self.tagged, forKey: .tagged)
        try container.encode(self.changes, forKey: .changes)
        try container.encodeIfPresent(self.body, forKey: .body)
        try container.encode(self.channel, forKey: .channel)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let versionString = try container.decode(String.self, forKey: .versionString)
        let train = try container.decodeIfPresent(Configuration.Train.self, forKey: .train)
        let tagged = try container.decodeIfPresent(Bool.self, forKey: .tagged) ?? false
        let changes = try container.decodeIfPresent([Category: [Change]].self, forKey: .changes) ?? [:]
        let body = try container.decodeIfPresent(String.self, forKey: .body)

        self.init(versionString: versionString, train: train, tagged: tagged, changes: changes, body: body)
    }
}

extension Release {
    init(
        version: Version,
        tagged: Bool,
        train: Configuration.Train?,
        body: String?,
        conventionalCommits: [ConventionalCommit],
        correspondingHashes: [ObjectID]
    ) {
        assert(conventionalCommits.count == correspondingHashes.count, "Array lengths do not match")

        self.versionString = version.description
        self.tagged = tagged
        self.train = train
        self.body = body

        let trailerName = Configuration.configuration
            .projectIdTrailerName

        self.changes = conventionalCommits.enumerated().reduce(into: [:], { result, element in
            let (index, cc) = element
            let header = cc.header

            if result[header.type] == nil {
                result[header.type] = []
            }

            result[header.type]?.append(Change(
                summary: header.summary,
                body: cc.body,
                commitHash: correspondingHashes[index].description,
                projectIds: trailerName == nil ? [] :
                    cc.trailers(named: trailerName!).map(\.value)
            ))
        })
    }

    func adding(
        prereleaseIdentifiers: [String] = [],
        buildIdentifiers: [String] = []
    ) throws -> Self {
        guard let version else {
            throw ReleaseError.invalidVersion(versionString)
        }

        let newVersion = version.adding(
            prereleaseIdentifiers: prereleaseIdentifiers,
            buildIdentifiers: buildIdentifiers
        )

        return Self(
            versionString: newVersion.description,
            train: train,
            tagged: tagged,
            changes: changes,
            body: body
        )
    }

    func adding(notes: String) -> Self {
        Self(
            versionString: versionString,
            train: train,
            tagged: tagged,
            changes: changes,
            body: notes
        )
    }

    func redacting(commitHashes: Bool, projectIds: Bool) -> Self {
        Self(
            versionString: versionString,
            train: train,
            tagged: tagged,
            changes: changes.reduce(into: [:], { partialResult, keypair in
                partialResult[keypair.key] = keypair.value.map {
                    $0.redacting(commitHash: commitHashes, projectIds: projectIds)
                }
            }),
            body: body
        )
    }
}

extension Release.Category {
    func describe() -> String {
        guard let category = Configuration.get(\.commitCategories).first(where: { $0.name == self }),
              let changelogName = category.changelogName else {
            return self
        }
        return changelogName
    }

    var allowedInReleaseDescription: Bool {
        guard let category = Configuration.get(\.commitCategories).first(where: { $0.name == self }),
              let excludeFromChangelog = category.excludeFromChangelog else {
            return true
        }
        return !excludeFromChangelog
    }
}

extension Release.Change: CustomStringConvertible {
    var description: String {
        var result = "- "
        if !commitHash.isEmpty {
            result += "\(commitHash.prefix(8)): "
        }
        result += "\(summary)"
        if !projectIds.isEmpty {
            result += " " + projectIds.map {
                "[\($0)]"
            }.joined(separator: " ")
        }
        return result
    }
}

extension Release.Change {
    func redacting(commitHash: Bool, projectIds: Bool) -> Self {
        Self(
            summary: summary,
            body: body,
            commitHash: commitHash ? "" : self.commitHash,
            projectIds: projectIds ? [] : self.projectIds
        )
    }
}

extension Release: CustomStringConvertible {
    var description: String {
        var result = "# \(train?.name ?? "Version") \(versionString)\(tagged ? "" : " (Not Tagged)"):\n\n"

        if let body {
            result.append("\(body)\n\n")
        }

        result.append("""
            \(changes.filter(\.key.allowedInReleaseDescription).reduce(into: "") { result, category in
                result += "## \(category.key.describe()):\n"
                result += category.value.map(\.description).joined(separator: "\n")
                result += "\n"
            })
            """
        )

        return result.trimmingCharacters(in: .newlines)
    }
}

extension Array<Release> {
    func show(_ format: ReleaseFormat, includeCommitHashes: Bool, includeProjectIds: Bool) throws -> StringOrData {
        var encodedValue = self

        if !includeCommitHashes || !includeProjectIds {
            encodedValue = encodedValue.map {
                $0.redacting(commitHashes: !includeCommitHashes, projectIds: !includeProjectIds)
            }
        }

        let result: StringOrData

        switch format {
        case .json:
            let encoder = JSONEncoder()
            result = try .init(encoder.encode(encodedValue))
        case .yaml:
            let encoder = YAMLEncoder()
            result = try .init(encoder.encode(encodedValue))
        case .plist:
            let encoder = PropertyListEncoder()
            result = try .init(encoder.encode(encodedValue))
        case .version:
            let versions = encodedValue.map(\.versionString).joined(separator: ",")
            result = .init(versions)
        case .text:
            let description = encodedValue.map(\.description).joined(separator: "\n")
            result = .init(description)
        }

        return result
    }
}

/// Convenience functions for creating one or more releases from an arbitrary range of commits. The public functions
/// are responsible for determining the appropriate ranges of commits from the available tags, and then pass these
/// ranges onto the private `releases()` function which is responsible for creating the actual Release objects.
extension Repositoryish {
    private typealias TaggedRelease = (tag: TagReferenceish, version: Version)
    private typealias ReleaseRange = (last: TaggedRelease?, release: ReferenceType)

    private func tagsAndVersions(for train: Configuration.Train?) throws -> [TaggedRelease] {
        try allTags().compactMap { (tag: TagReferenceish) -> TaggedRelease? in
            guard let version = Version(
                prefix: train?.tagPrefix,
                versionString: tag.name
            ) else { return nil }

            return (tag: tag, version: version)
        }.sorted { $0.version < $1.version }
    }

    private func lastReachableTag(
        among references: ArraySlice<TaggedRelease>,
        from: ObjectID,
        inclusive: Bool = false,
        prerelease: Bool = false
    ) throws -> TaggedRelease? {
        try references.last {
            try (inclusive || $0.tag.oid != from) &&
                (prerelease || !$0.version.isPrerelease) &&
                isReachable($0.tag.oid, from: from)
        }
    }

    private func releases(
        for train: Configuration.Train?,
        fromRanges ranges: [ReleaseRange],
        untaggedRangePrereleaseChannel: String? = nil,
        forceLatestVersionTo forcedVersion: Version? = nil
    ) throws -> [Release] {
        try ranges.reduce(into: []) {
            let repoCommits = try commits(from: $1.release.oid, since: $1.last?.tag.oid)
            var badCommits: Int = 0
            let commits: [(oid: OID, cc: ConventionalCommit)] = repoCommits.compactMap {
                do {
                    // Attempt to properly parse a conventional commit. If we can't, then fake one using the
                    // commit subject and body.
                    let commit = try ConventionalCommit(message: $0.message)
                    guard let categories = Configuration.configuration.commitCategories else {
                        return ($0.oid, commit)
                    }

                    guard categories.contains(where: { $0.name == commit.header.type }) == true else {
                        badCommits += 1
                        return nil
                    }

                    return ($0.oid, commit)
                } catch {
                    badCommits += 1
                    return nil
                }
            }

            if badCommits > 0 {
                Gluon.print(
                    """
                    Warning: \(badCommits) commit\(badCommits == 1 ? "" : "s") did not match the conventional commit \
                    format, or had a type that was not configured in the repository's gluon configuration.
                    """,
                    error: true
                )
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

            let conventionalCommits = commits.map(\.cc)

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
            } else if let forcedVersion {
                version = forcedVersion
            } else if let last = $1.last {
                version = conventionalCommits.nextVersion(
                    after: last.version,
                    prereleaseChannel: untaggedRangePrereleaseChannel
                )
            } else {
                version = Version(major: 0, minor: 0, patch: 1)
            }

            $0.append(.init(
                version: version,
                tagged: tagged,
                train: train,
                body: body,
                conventionalCommits: conventionalCommits,
                correspondingHashes: commits.map(\.oid)
            ))
        }
    }

    public func release(for train: Configuration.Train?, exactVersion version: Version) throws -> Release? {
        let taggedReleases = try tagsAndVersions(for: train)
        let index = taggedReleases.binarySearch { $0.version < version }

        guard 0 <= index && index < taggedReleases.count else {
            return nil
        }

        let releaseTag = taggedReleases[index]
        guard releaseTag.version == version else {
            return nil
        }

        let lastVersion = try lastReachableTag(
            among: taggedReleases[0..<index],
            from: releaseTag.tag.oid,
            prerelease: false
        )

        return try releases(for: train, fromRanges: [(lastVersion, releaseTag.tag)]).first
    }

    public func latestRelease(
        for train: Configuration.Train?,
        allowDirty: Bool,
        untaggedPrereleaseChannel: String?,
        forceLatestVersionTo forcedVersion: Version?
    ) throws -> Release? {
        let head: ReferenceType = try currentBranch() ?? HEAD()
        let taggedReleases = try tagsAndVersions(for: train)

        let lastVersion = try lastReachableTag(
            among: taggedReleases[...],
            from: head.oid,
            prerelease: untaggedPrereleaseChannel != nil
        )

        if let thisTag = head as? TagReferenceish {
            return try releases(
                for: train,
                fromRanges: [(lastVersion, thisTag)]
            ).first
        } else if let thisVersion = try lastReachableTag(among: taggedReleases[...], from: head.oid, inclusive: true),
            thisVersion.tag.oid == head.oid {
            // We could have been passed a ReferenceType for HEAD that wasn't a tag, even if HEAD is in fact tagged.
            // If we do a reverse lookup for the latest tag and it happens to be the same OID as HEAD, use that tag
            // as the reference type instead. This lets us make sure we set the "tagged" property correctly.
            return try releases(
                for: train,
                fromRanges: [(lastVersion, thisVersion.tag)]
            ).first
        } else if allowDirty {
            return try releases(
                for: train,
                fromRanges: [(lastVersion, head)],
                untaggedRangePrereleaseChannel: untaggedPrereleaseChannel,
                forceLatestVersionTo: forcedVersion
            ).first
        } else if let lastVersion {
            return try release(
                for: train,
                exactVersion: lastVersion.version
            )
        } else {
            return nil
        }
    }

    public func allReleases(
        for train: Configuration.Train?,
        allowDirty: Bool,
        untaggedPrereleaseChannel: String?,
        forceLatestVersionTo forcedVersion: Version?
    ) throws -> [Release] {
        let head: ReferenceType = try currentBranch() ?? HEAD()
        let taggedReleases = try tagsAndVersions(for: train)

        var ranges: [ReleaseRange] = try taggedReleases
            .filter { !$0.version.isPrerelease }
            .enumerated()
            .reduce(into: []) { result, element in
                let (i, (tag, _)) = element
                let lastVersion = try lastReachableTag(
                    among: taggedReleases[0..<i],
                    from: tag.oid
                )
                result.append((lastVersion, tag))
            }

        if allowDirty, let last = ranges.last, last.release.oid != head.oid {
            let lastUntaggedVersion = try lastReachableTag(
                among: taggedReleases[...],
                from: head.oid
            )
            ranges.append((lastUntaggedVersion, head))
        }

        // We want the most recent versions first.
        return try releases(
            for: train,
            fromRanges: ranges.reversed(),
            untaggedRangePrereleaseChannel: untaggedPrereleaseChannel,
            forceLatestVersionTo: forcedVersion
        )
    }
}

enum ReleaseError: Error {
    case invalidVersion(String)
}
