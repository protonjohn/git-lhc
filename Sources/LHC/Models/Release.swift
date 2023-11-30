//
//  Release.swift
//
//  Created by John Biggs on 11.10.23.
//

import Foundation
import Version
import SwiftGit2
import Yams
import LHCInternal

/// A software release.
public struct Release {
    /// The category for a given change, denoted by its conventional commit type.
    public typealias Category = String

    /// The string for this release's version. May or may not parse into a semantic version.
    public let versionString: String
    /// The train name associated with this release.
    public let train: String?
    /// Whether or not this release has been tagged in the repository history yet.
    public let tagged: Bool
    /// The changes associated with this release, grouped by category.
    public let changes: [Category: [Change]]

    /// The body of the tag associated with this release. Normally contains release notes and other metadata.
    public let body: String?

    /// The parsed version of this release.
    public var version: Version? {
        Version(versionString)
    }

    /// The parsed version of this release, omitting any prerelease or build identifiers.
    public var shortVersion: Version? {
        guard let version else { return nil }
        return Version(version.major, version.minor, version.patch)
    }

    /// The channel associated with this release.
    public var channel: ReleaseChannel {
        for identifier in version?.prereleaseIdentifiers ?? [] {
            if let channel = ReleaseChannel(rawValue: identifier) {
                return channel
            }
        }

        return .production
    }

    /// A software change, adhering to conventional commit syntax.
    public struct Change: Codable {
        /// The summary of the change.
        public let summary: String
        /// The body of the commit.
        public let body: String?
        /// The hash of the commit, represented as a a string.
        public let commitHash: String
        /// The project IDs associated with this change, if the project ID prefix has been set in the configuration.
        public let projectIds: [String]
    }
}

/// The channel associated with a release.
///
/// Release channels are used to stage new releases before they are sent to the general user population. Each channel
/// can have a different use case; for example, alpha builds may only ever be sent to internal members for testing,
/// while beta builds get sent to a limited subset of the user population.
public enum ReleaseChannel: String, CaseIterable, Codable {
    case alpha
    case beta
    case releaseCandidate = "rc"
    case production

    /// The list of recognized prerelease channels.
    public static var prereleaseChannels: [Self] = [.alpha, .beta, .releaseCandidate]

    public var isPrerelease: Bool {
        Self.prereleaseChannels.contains(self)
    }

    /// The release channel specified by the current environment variables.
    public static var environment: Self? {
        guard let value = LHCEnvironment.channel.value,
              let channel = Self(rawValue: value) else {
            return nil
        }

        return channel
    }
}

extension Version {
    /// The release channel associated with a given version.
    ///
    /// If the version contains any prerelease identifiers, this will return that value. Otherwise, it assumes the
    /// version is associated with a production release.
    public var releaseChannel: ReleaseChannel {
        for identifier in prereleaseIdentifiers {
            if let channel = ReleaseChannel(rawValue: identifier) {
                return channel
            }
        }
        return .production
    }
}

public enum ReleaseFormat: String, CaseIterable {
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
        case body = "changelog"
        case channel
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.versionString, forKey: .versionString)
        try container.encodeIfPresent(self.shortVersion?.description, forKey: .shortVersion)
        try container.encodeIfPresent(self.train, forKey: .train)
        try container.encode(self.tagged, forKey: .tagged)
        try container.encode(self.changes, forKey: .changes)
        try container.encodeIfPresent(self.body, forKey: .body)
        try container.encode(self.channel, forKey: .channel)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let versionString = try container.decode(String.self, forKey: .versionString)
        let train = try container.decodeIfPresent(String.self, forKey: .train)
        let tagged = try container.decodeIfPresent(Bool.self, forKey: .tagged) ?? false
        let changes = try container.decodeIfPresent([Category: [Change]].self, forKey: .changes) ?? [:]
        let body = try container.decodeIfPresent(String.self, forKey: .body)

        self.init(versionString: versionString, train: train, tagged: tagged, changes: changes, body: body)
    }
}

extension Release {
    public init(
        version: Version,
        tagged: Bool,
        train: String?,
        body: String?,
        conventionalCommits: [ConventionalCommit],
        correspondingHashes: [ObjectID],
        projectIdTrailerName trailerName: String? = nil
    ) {
        assert(conventionalCommits.count == correspondingHashes.count, "Array lengths do not match")

        self.versionString = version.description
        self.tagged = tagged
        self.train = train
        self.body = body

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

    public func adding(
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

    public func adding(notes: String) -> Self {
        Self(
            versionString: versionString,
            train: train,
            tagged: tagged,
            changes: changes,
            body: notes
        )
    }

    public func redacting(commitHashes: Bool, projectIds: Bool) -> Self {
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

    public func describe(options: Configuration.Options? = nil) -> String? {
        var result = "# \(train ?? "Version") \(versionString)\(tagged ? "" : " (Not Tagged)"):\n\n"

        if let body {
            result.append("\(body)\n\n")
        }

        result.append("""
            \(changes.reduce(into: "") { result, category in
                guard let categoryDescription = category.key.describe(options: options) else {
                    return
                }
                result += "## \(categoryDescription):\n"
                result += category.value.map(\.description).joined(separator: "\n")
                result += "\n"
            })
            """
        )

        return result.trimmingCharacters(in: .newlines)
    }
}

extension Release.Category {
    public func describe(options: Configuration.Options? = nil) -> String? {
        guard let options else {
            return self
        }

        if options.changelogExcludedCategories?.contains(self) == true {
            return nil
        }

        guard let index = options.commitCategories?.firstIndex(of: self),
              options.commitCategoryDisplayNames?.count == options.commitCategories?.count,
              let displayName = options.commitCategoryDisplayNames?[index] else {
            return self
        }

        return displayName
    }
}

extension Release.Change: CustomStringConvertible {
    public var description: String {
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
    public func redacting(commitHash: Bool, projectIds: Bool) -> Self {
        Self(
            summary: summary,
            body: body,
            commitHash: commitHash ? "" : self.commitHash,
            projectIds: projectIds ? [] : self.projectIds
        )
    }
}

/// Convenience functions for creating one or more releases from an arbitrary range of commits. The public functions
/// are responsible for determining the appropriate ranges of commits from the available tags, and then pass these
/// ranges onto the private `releases()` function which is responsible for creating the actual Release objects.
extension Repositoryish {
    private typealias TaggedRelease = (tag: TagReferenceish, version: Version)
    private typealias ReleaseRange = (last: TaggedRelease?, release: ReferenceType)

    private func tagsAndVersions(options: Configuration.Options?) throws -> [TaggedRelease] {
        try allTags().compactMap { (tag: TagReferenceish) -> TaggedRelease? in
            guard let version = Version(
                prefix: options?.tagPrefix,
                versionString: tag.name
            ) else { return nil }

            return (tag: tag, version: version)
        }.sorted { $0.version < $1.version }
    }

    private func lastReachableRelease(
        among references: ArraySlice<TaggedRelease>,
        from: ObjectID,
        inclusive: Bool = false
    ) throws -> TaggedRelease? {
        try references.last {
            try (inclusive || $0.tag.oid != from) &&
                $0.version.releaseChannel == .production &&
                isReachable($0.tag.oid, from: from)
        }
    }

    private func taggedReleaseRanges(_ taggedReleases: [TaggedRelease]) throws -> [ReleaseRange] {
        return try taggedReleases.enumerated().reduce(into: []) { result, element in
            let (i, (tag, _)) = element
            let lastVersion = try lastReachableRelease(
                among: taggedReleases[0..<i],
                from: tag.oid
            )
            result.append((lastVersion, tag))
        }
    }

    private func releases(
        fromRanges ranges: [ReleaseRange],
        untaggedRangeReleaseChannel: ReleaseChannel = .production,
        forceLatestVersionTo forcedVersion: Version? = nil,
        options: Configuration.Options? = nil
    ) throws -> ([Release], badCommits: [Commitish]) {
        var versionsSoFar: [Version] = []
        var result: [Release] = []
        var badCommits: [Commitish] = []

        for (last, release) in ranges {
            let repoCommits = try commits(from: release.oid, since: last?.tag.oid)
            let commits: [(oid: OID, cc: ConventionalCommit)] = repoCommits.compactMap {
                do {
                    // Attempt to properly parse a conventional commit. If we can't, then fake one using the
                    // commit subject and body.
                    let commit = try ConventionalCommit(message: $0.message)
                    guard let categories = options?.commitCategories else {
                        return ($0.oid, commit)
                    }

                    guard categories.contains(commit.header.type) == true else {
                        badCommits.append($0)
                        return nil
                    }

                    return ($0.oid, commit)
                } catch {
                    badCommits.append($0)
                    return nil
                }
            }

            #if false
            if badCommits > 0 {
                Internal.print(
                    """
                    Warning: \(badCommits) commit\(badCommits == 1 ? "" : "s") did not match the conventional commit \
                    format, or had a type that was not configured in the repository's lhc configuration.
                    """,
                    error: true
                )
            }
            #endif

            var body: String?
            if let tagReference = release as? TagReferenceish,
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
            if let releaseTag = release as? TagReferenceish,
               let taggedVersion = Version(
                   prefix: options?.tagPrefix,
                   versionString: releaseTag.name
               )
            {
                version = taggedVersion
                tagged = true
            } else if let forcedVersion {
                version = forcedVersion
            } else if let last {
                version = conventionalCommits.nextVersion(
                    after: versionsSoFar + [last.version],
                    options: options
                )
            } else {
                version = Version(major: 0, minor: 0, patch: 1)
            }

            versionsSoFar.append(version)
            result.append(.init(
                version: version,
                tagged: tagged,
                train: options?.trainDisplayName ?? options?.train,
                body: body,
                conventionalCommits: conventionalCommits,
                correspondingHashes: commits.map(\.oid),
                projectIdTrailerName: options?.projectIdTrailerName
            ))
        }
        return (result, badCommits)
    }

    public func release(exactVersion version: Version, options: Configuration.Options?) throws -> Release? {
        let taggedReleases = try tagsAndVersions(options: options)
        let index = taggedReleases.binarySearch { $0.version < version }

        guard 0 <= index && index < taggedReleases.count else {
            return nil
        }

        let releaseTag = taggedReleases[index]
        guard releaseTag.version == version else {
            return nil
        }

        let lastVersion = try lastReachableRelease(
            among: taggedReleases[0..<index],
            from: releaseTag.tag.oid
        )

        return try releases(fromRanges: [(lastVersion, releaseTag.tag)], options: options).0.first
    }

    public func latestRelease(
        allowDirty: Bool,
        untaggedReleaseChannel: ReleaseChannel = .production,
        forceLatestVersionTo forcedVersion: Version?,
        options: Configuration.Options? = nil
    ) throws -> Release? {
        let head: ReferenceType = try currentBranch() ?? HEAD()
        let taggedReleases = try tagsAndVersions(options: options)

        let lastVersion = try lastReachableRelease(
            among: taggedReleases[...],
            from: head.oid
        )

        if let thisTag = head as? TagReferenceish {
            return try releases(
                fromRanges: [(lastVersion, thisTag)],
                options: options
            ).0.first
        } else if let thisVersion = try lastReachableRelease(among: taggedReleases[...], from: head.oid, inclusive: true),
            thisVersion.tag.oid == head.oid {
            // We could have been passed a ReferenceType for HEAD that wasn't a tag, even if HEAD is in fact tagged.
            // If we do a reverse lookup for the latest tag and it happens to be the same OID as HEAD, use that tag
            // as the reference type instead. This lets us make sure we set the "tagged" property correctly.
            return try releases(
                fromRanges: [(lastVersion, thisVersion.tag)],
                options: options
            ).0.first
        } else if allowDirty {
            // The tag hasn't been computed yet, so we'll need to create one.
            // For this, we need to make sure that `releases' has seen all of the possible release tags for the given
            // release channel, if that release channel isn't production, in order to calculate the version correctly.
            var ranges = [(lastVersion, head)]
            if untaggedReleaseChannel.isPrerelease {
                let otherVersions = try taggedReleaseRanges(
                    taggedReleases.filter {
                        $0.version.releaseChannel == untaggedReleaseChannel &&
                        $0.version > (lastVersion?.version ?? Version(0, 0, 0))
                    }
                )
                ranges = otherVersions + ranges
            }

            // We pass multiple values to `releases' so that it can see all of the prereleases for a channel, so make
            // sure we only return the last value with the highest version, which
            // should be our element.
            return try releases(
                fromRanges: ranges,
                untaggedRangeReleaseChannel: untaggedReleaseChannel,
                forceLatestVersionTo: forcedVersion,
                options: options
            ).0.last
        } else if let lastVersion {
            return try release(
                exactVersion: lastVersion.version,
                options: options
            )
        } else {
            return nil
        }
    }

    public func allReleases(
        allowDirty: Bool,
        untaggedReleaseChannel: ReleaseChannel = .production,
        forceLatestVersionTo forcedVersion: Version?,
        options: Configuration.Options? = nil
    ) throws -> [Release] {
        let head: ReferenceType = try currentBranch() ?? HEAD()
        let taggedReleases = try tagsAndVersions(options: options)

        var ranges: [ReleaseRange] = try taggedReleaseRanges(
            taggedReleases.filter { $0.version.releaseChannel == .production }
        )

        if allowDirty, let last = ranges.last, last.release.oid != head.oid {
            let lastUntaggedVersion = try lastReachableRelease(
                among: taggedReleases[...],
                from: head.oid
            )
            ranges.append((lastUntaggedVersion, head))
        }

        // We want the most recent versions first.
        return try releases(
            fromRanges: ranges.reversed(),
            untaggedRangeReleaseChannel: untaggedReleaseChannel,
            forceLatestVersionTo: forcedVersion,
            options: options
        ).0
    }
}

public enum ReleaseError: Error {
    case invalidVersion(String)
}
