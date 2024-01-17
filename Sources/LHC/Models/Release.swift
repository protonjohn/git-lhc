//
//  Release.swift
//
//  Created by John Biggs on 11.10.23.
//

import Foundation
import Version
import SwiftGit2
import Stencil
import LHCInternal

/// A software release.
public struct Release {
    public typealias Trailer = ConventionalCommit.Trailer

    /// The category for a given change, denoted by its conventional commit type.
    public typealias Category = String

    /// The name of the tag designating this release, if any.
    public let tagName: String?

    /// The hash of the object designating this release, if any.
    public let objectHash: String?

    /// The string for this release's version, often the same as the tag name. Not necessarily a semantic version.
    public let versionString: String

    /// The train name associated with this release.
    public let train: String?

    /// The changes associated with this release, grouped by category.
    public let changes: [Category: [Change]]

    /// The body of the tag associated with this release. Normally contains release notes.
    public let body: String?

    /// Trailers added to the release's tag body.
    public let trailers: [Trailer]?

    /// Attributes attached to the release tag through `git-lhc attr`.
    public let attributes: [Trailer]?

    /// A list of checklist names which have been evaluated for this release since its creation, if any.
    public let checklists: [String]?

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
        /// A list of checklist names which have been evaluated for this change since it was merged, if any.
        public let checklists: [String]?
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
        case tagName = "tag_name"
        case objectHash = "object_hash"
        case changes
        case body = "changelog"
        case channel
        case trailers = "tag_trailers"
        case attributes = "attributes"
        case checklists = "checklists"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.versionString, forKey: .versionString)
        try container.encodeIfPresent(self.objectHash, forKey: .objectHash)
        try container.encodeIfPresent(self.shortVersion?.description, forKey: .shortVersion)
        try container.encodeIfPresent(self.train, forKey: .train)
        try container.encodeIfPresent(self.tagName, forKey: .tagName)
        try container.encode(self.changes, forKey: .changes)
        try container.encodeIfPresent(self.body, forKey: .body)
        try container.encode(self.channel, forKey: .channel)
        try container.encodeIfPresent(self.attributes, forKey: .attributes)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let versionString = try container.decode(String.self, forKey: .versionString)
        let objectHash = try container.decodeIfPresent(String.self, forKey: .objectHash)
        let train = try container.decodeIfPresent(String.self, forKey: .train)
        let tagName = try container.decodeIfPresent(String.self, forKey: .tagName)
        let changes = try container.decodeIfPresent([Category: [Change]].self, forKey: .changes) ?? [:]
        let body = try container.decodeIfPresent(String.self, forKey: .body)
        let checklists = try container.decodeIfPresent([String].self, forKey: .checklists)

        let trailers: [Trailer]? = try container.decodeIfPresent([String: String].self, forKey: .trailers)?
            .reduce(into: []) {
                $0.append(.init(key: $1.key, value: $1.value))
            }

        let attributes: [Trailer]? = try container.decodeIfPresent([String: String].self, forKey: .attributes)?
            .reduce(into: []) {
                $0.append(.init(key: $1.key, value: $1.value))
            }

        self.init(
            tagName: tagName,
            objectHash: objectHash,
            versionString: versionString,
            train: train,
            changes: changes,
            body: body,
            trailers: trailers,
            attributes: attributes,
            checklists: checklists
        )
    }
}

extension Release {
    public init(
        version: Version,
        tagName: String?,
        objectID: ObjectID?,
        train: String?,
        body: String?,
        trailers: [Trailer]?,
        attributes: [Trailer]?,
        conventionalCommits: [ConventionalCommit],
        correspondingHashes: [ObjectID],
        checklistNames: [ObjectID: [String]]?,
        projectIdTrailerName trailerName: String? = nil
    ) {
        assert(conventionalCommits.count == correspondingHashes.count, "Array lengths do not match")

        self.versionString = version.description
        self.tagName = tagName
        self.objectHash = objectID?.description
        self.train = train
        self.trailers = trailers
        self.attributes = attributes
        self.body = body

        if let objectID {
            self.checklists = checklistNames?[objectID]
        } else {
            self.checklists = nil
        }

        self.changes = conventionalCommits.enumerated().reduce(into: [:], { result, element in
            let (index, cc) = element
            let header = cc.header

            if result[header.type] == nil {
                result[header.type] = []
            }

            let oid = correspondingHashes[index]
            result[header.type]?.append(Change(
                summary: header.summary,
                body: cc.body,
                commitHash: oid.description,
                projectIds: trailerName == nil ? [] :
                    cc.trailers(named: trailerName!).map(\.value),
                checklists: checklistNames?[oid]
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
            tagName: tagName,
            objectHash: objectHash,
            versionString: newVersion.description,
            train: train,
            changes: changes,
            body: body,
            trailers: trailers,
            attributes: attributes,
            checklists: checklists
        )
    }

    public func adding(notes: String) -> Self {
        Self(
            tagName: tagName,
            objectHash: objectHash,
            versionString: versionString,
            train: train,
            changes: changes,
            body: notes,
            trailers: trailers,
            attributes: attributes,
            checklists: checklists
        )
    }

    public func redacting(commitHashes: Bool, projectIds: Bool, checklists: Bool) -> Self {
        Self(
            tagName: tagName,
            objectHash: objectHash,
            versionString: versionString,
            train: train,
            changes: changes.reduce(into: [:], { partialResult, keypair in
                partialResult[keypair.key] = keypair.value.map {
                    $0.redacting(commitHash: commitHashes, projectIds: projectIds, checklists: checklists)
                }
            }),
            body: body,
            trailers: trailers,
            attributes: attributes,
            checklists: self.checklists
        )
    }

    public func describe(options: Configuration.Options? = nil) -> String? {
        var result = "# \(train ?? "Version") \(versionString)\(tagName != nil ? "" : " (Not Tagged)"):\n\n"

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
    public func redacting(commitHash: Bool, projectIds: Bool, checklists: Bool) -> Self {
        Self(
            summary: summary,
            body: body,
            commitHash: commitHash ? "" : self.commitHash,
            projectIds: projectIds ? [] : self.projectIds,
            checklists: checklists ? [] : self.checklists
        )
    }
}

public enum ReleaseError: Error {
    case invalidVersion(String)
}

/// Convenience functions for creating one or more releases from an arbitrary range of commits. The public functions
/// are responsible for determining the appropriate ranges of commits from the available tags, and then pass these
/// ranges onto the private `releases()` function which is responsible for creating the actual Release objects.
extension Repositoryish {
    private typealias Trailer = ConventionalCommit.Trailer
    private typealias TaggedRelease = (object: ObjectType, version: Version)
    private typealias ReleaseRange = (last: TaggedRelease?, release: ObjectType)

    private func tagsAndVersions(options: Configuration.Options?) throws -> [TaggedRelease] {
        let result = try allTags().compactMap { (tag: TagReferenceish) -> TaggedRelease? in
            guard let version = Version(
                prefix: options?.tagPrefix,
                versionString: tag.name
            ) else { return nil }

            guard let object = try? object(tag.tagOid ?? tag.oid) else { return nil }

            return (object: object, version: version)
        }.sorted { $0.version < $1.version }
        for item in result {
            print(item)
        }
        return result
    }

    private func lastReachableRelease(
        among objects: ArraySlice<TaggedRelease>,
        from: ObjectID,
        inclusive: Bool = false
    ) throws -> TaggedRelease? {
        try objects.last {
            guard let target = $0.object.commitOid else {
                throw GitError(
                    code: .invalid,
                    detail: .object,
                    description: "\($0.object) should be either a tag or a commit"
                )
            }
            return try (inclusive || target != from) &&
                $0.version.releaseChannel == .production &&
                isReachable(target, from: from)
        }
    }

    private func taggedReleaseRanges(_ taggedReleases: [TaggedRelease]) throws -> [ReleaseRange] {
        return try taggedReleases.enumerated().reduce(into: []) { result, element in
            let (i, (tag, _)) = element

            guard let target = tag.commitOid else {
                throw GitError(
                    code: .invalid,
                    detail: .object,
                    description: "\(tag.oid) should be either a tag or a commit"
                )
            }

            let lastVersion = try lastReachableRelease(
                among: taggedReleases[0..<i],
                from: target
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

        let checklistRefNames = try? checklistRefs(options: options)
        var objectChecklistNames: [ObjectID: [String]] = [:]

        for (last, release) in ranges {
            let lastTarget = last?.object.commitOid
            guard let releaseTarget = release.commitOid else {
                throw GitError(
                    code: .invalid,
                    detail: .object,
                    description: "\(release.oid) should be either a tag or a commit"
                )
            }
            let repoCommits = try commits(from: releaseTarget, since: lastTarget)
            let commits: [(oid: OID, cc: ConventionalCommit)] = repoCommits.compactMap { commit in
                do {
                    var attributes: [Trailer]?
                    if let attrsRef = options?.attrsRef,
                       let note = try? note(for: commit.oid, notesRef: attrsRef) {
                        attributes = note.attributes.trailers
                    }

                    if let checklistRefNames {
                        let checklists = checklistNames(fromRefNames: checklistRefNames, withNotesFor: commit.oid)
                        objectChecklistNames[commit.oid] = (checklists.isEmpty ? nil : checklists)
                    }

                    // Attempt to properly parse a conventional commit. If we can't, then fake one using the
                    // commit subject and body.
                    let cc = try ConventionalCommit(message: commit.message, attributes: attributes)
                    guard let categories = options?.commitCategories else {
                        return (commit.oid, cc)
                    }

                    guard categories.contains(cc.header.type) == true else {
                        badCommits.append(commit)
                        return nil
                    }

                    return (commit.oid, cc)
                } catch {
                    badCommits.append(commit)
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
            var trailers: [Trailer]?
            var attributes: [Trailer]?

            if let tag = release as? Tagish {
                if let conventionalTag = try? ConventionalCommit(message: tag.message) {
                    // Annotated tags formatted like conventional commits look like:
                    // release(<train name>): Version 3.0.1
                    //
                    // <body follows>
                    //
                    // <trailers follow optionally>
                    //
                    // To avoid duplicating information, we'll only put the body here if the commit parses correctly.
                    body = conventionalTag.body
                    trailers = conventionalTag.trailers
                } else {
                    body = tag.message
                }

                if let attrsRef = options?.attrsRef,
                   let note = try? note(for: tag.oid, notesRef: attrsRef) {
                    attributes = note.attributes.trailers
                }

                // Note: we don't have to worry if this is a lightweight tag, since the checklists would have been
                // captured by the loop above.
                if let checklistRefNames {
                    let checklists = checklistNames(fromRefNames: checklistRefNames, withNotesFor: tag.oid)
                    objectChecklistNames[tag.oid] = (checklists.isEmpty ? nil : checklists)
                }
            }

            let conventionalCommits = commits.map(\.cc)

            var tagName: String?
            var tagOid: ObjectID?
            let version: Version
            if let releaseTag = release as? Tagish,
               let taggedVersion = Version(
                   prefix: options?.tagPrefix,
                   versionString: releaseTag.name
               )
            {
                version = taggedVersion
                tagName = releaseTag.name
                tagOid = releaseTag.oid
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
            result.append(Release(
                version: version,
                tagName: tagName,
                objectID: tagOid ?? commits.first?.oid,
                train: options?.trainDisplayName ?? options?.train,
                body: body,
                trailers: trailers,
                attributes: attributes,
                conventionalCommits: conventionalCommits,
                correspondingHashes: commits.map(\.oid),
                checklistNames: objectChecklistNames,
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

        guard let releaseTarget = releaseTag.object.commitOid else {
            throw GitError(
                code: .invalid,
                detail: .object,
                description: "\(releaseTag.object.oid) should be either a tag or a commit"
            )
        }

        let lastVersion = try lastReachableRelease(
            among: taggedReleases[0..<index],
            from: releaseTarget
        )

        return try releases(fromRanges: [(lastVersion, releaseTag.object)], options: options).0.first
    }

    public func latestRelease(
        allowDirty: Bool,
        untaggedReleaseChannel: ReleaseChannel = .production,
        forceLatestVersionTo forcedVersion: Version?,
        target: ObjectID? = nil,
        options: Configuration.Options? = nil
    ) throws -> Release? {
        let head: ReferenceType = try currentBranch() ?? HEAD()
        let taggedReleases = try tagsAndVersions(options: options)

        let lastVersion = try lastReachableRelease(
            among: taggedReleases[...],
            from: head.oid
        )

        if let thisTag = head as? TagReferenceish {
            let oid = thisTag.tagOid ?? thisTag.oid
            let object = try object(oid)
            return try releases(
                fromRanges: [(lastVersion, object)],
                options: options
            ).0.first
        } else if let thisVersion = try lastReachableRelease(
                among: taggedReleases[...],
                from: head.oid,
                inclusive: true
            ),
            thisVersion.object.commitOid == head.oid {
            // We could have been passed a ReferenceType for HEAD that wasn't a tag, even if HEAD is in fact tagged.
            // If we do a reverse lookup for the latest tag and it happens to be the same OID as HEAD, use that tag
            // as the reference type instead. This lets us make sure we set the "tagged" property correctly.
            return try releases(
                fromRanges: [(lastVersion, thisVersion.object)],
                options: options
            ).0.first
        } else if allowDirty {
            // The tag hasn't been computed yet, so we'll need to create one.
            // For this, we need to make sure that `releases' has seen all of the possible release tags for the given
            // release channel, if that release channel isn't production, in order to calculate the version correctly.
            let object = try commit(head.oid) as ObjectType
            var ranges = [(lastVersion, object)]
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
        allowDirty: Bool = false,
        forceLatestVersionTo forcedVersion: Version? = nil,
        channel: ReleaseChannel? = .production,
        target: ObjectID? = nil,
        options: Configuration.Options? = nil
    ) throws -> [Release] {
        let target = try target ?? (currentBranch() ?? HEAD()).oid
        var taggedReleases = try tagsAndVersions(options: options)

        if let channel {
            taggedReleases = taggedReleases.filter {
                $0.version.releaseChannel == channel
            }
        }

        var ranges: [ReleaseRange] = try taggedReleaseRanges(taggedReleases)

        let object = try object(target)
        if allowDirty, let last = ranges.last, last.release.oid != target {
            let lastUntaggedVersion = try lastReachableRelease(
                among: taggedReleases[...],
                from: target
            )
            ranges.append((lastUntaggedVersion, object))
        }

        // We want the most recent versions first.
        return try releases(
            fromRanges: ranges.reversed(),
            untaggedRangeReleaseChannel: channel ?? .production,
            forceLatestVersionTo: forcedVersion,
            options: options
        ).0
    }
}

extension Stencil.Environment {
    func renderRelease(
        templateName: String,
        release: Release,
        includeChecklists: Bool,
        repo: Repositoryish,
        options: Configuration.Options?
    ) throws -> [String: String?] {
        var context: [String: Any] = [:]

        context["release"] = release

        let subpath = options?.checklistOutputDir ?? "checklists/"
        let refroot = options?.checklistRefRootWithTrailingSlash ?? "refs/notes/checklists/"

        var checklistContents: [String: String] = [:]
        if includeChecklists {
            var oids: [ObjectID: [String]] = [:]
            if let hash = release.objectHash,
               let oid = ObjectID(string: hash),
               let checklists = release.checklists {
                oids[oid] = checklists
            }

            for (_, changes) in release.changes {
                for change in changes {
                    guard let checklists = change.checklists,
                          let oid = ObjectID(string: change.commitHash) else { continue }
                    oids[oid] = checklists
                }
            }

            checklistContents = oids.reduce(into: [:], {
                for name in $1.value {
                    guard let note = try? repo.note(for: $1.key, notesRef: refroot + name) else { continue }
                    $0[subpath + $0.description + "/\(name)"] = note.message
                }
            })
        }

        let templateContents = try renderTemplates(
            nameOrRoot: templateName,
            additionalContext: context
        )

        return templateContents.merging(checklistContents, uniquingKeysWith: { lhs, rhs in lhs })
    }
}
