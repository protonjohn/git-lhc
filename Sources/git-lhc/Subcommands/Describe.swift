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
import Stencil
import DictionaryCoder
import System

struct Describe: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Display the changelog for the specified version(s)."
    )

    @OptionGroup()
    var parent: LHC.Options

    @Option(
        name: .shortAndLong,
        help: """
            Which parts of the changelog to show. Possible values are:

            - all: show all tagged versions for a given channel.
            - HEAD: show the version at HEAD.
                * If HEAD is tagged, shows the most senior release for HEAD.
                * If HEAD is not tagged or the tag's channel does not match, simulates a release for the given channel.
            - latest: show the latest tagged version for a given channel.
            - <version>: when combined with --train (if using a tag prefix), show that specific version. \
            Release channel is inferred from the version.
            - <tag>: infer both train and release channel from the tag name, and show that specific version.
            """
    )
    var show: OutputSpec = .latest

    @Option(
        name: .shortAndLong,
        help: "The output format to use. Possible values are \(ReleaseFormat.possibleValues)."
    )
    var format: ReleaseFormat = .text

    @Option(
        name: .customLong("template"),
        help: """
            One or more templates to evaluate, according to the configured template directories.

            A release template gets evaluated with several pre-defined variables:
            - `release`, containing the release description as available in the release json
            - `config`, containing the evaluated configuration for the given train and version
            - ``
            """
    )
    var templates: [String] = []

    @Option(
        name: [.customShort("D", allowingJoined: true), .customLong("define")],
        help: """
            Define an initial property before evaluating the lhc config file, which is provided in the context for \
            arguments specified by `--template`.
            """
    )
    var defines: [LHC.Define] = []

    @Option(
        name: [.short, .customLong("output")],
        help: """
            An optional path to an output file or directory.

            If `--output` is a file, any argument specified by `--template` will result in an error.
            If `--output` is a directory (denoted by a trailing slash), the release description will be named \
            `release.txt`, `release.json`, or `release.plist, depending on the format, and placed in the specified \
            directory. Any argument specified by `--template` will also be evaluated and placed in this directory \
            according to its original filename, with any `.template` file extensions removed.
            If `--output` is a directory `--show all` is specified, the output specified above will be evaluated \
            for each release, and placed in a subdirectory corresponding with that release's version tag.
            """,
        transform: URL.createFromPathOrThrow(_:)
    )
    var outputPath: URL?

    @Option(
        name: [.customLong("checklist-output")],
        help: """
            A subdirectory of the output directory (or the current working directory if no value is provided for \
            `--output`) in which all checklists evaluated for the current release -- including all included changes \
            -- are written.
            """,
        transform: URL.createFromPathOrThrow(_:)
    )
    var checklistOutputPath: URL?

    @Flag(help: "Whether to include project IDs in release descriptions.")
    var redactProjectIds: Bool = false

    @Flag(help: "Whether to include commit hashes in release descriptions.")
    var redactCommitHashes: Bool = false

    @Flag(help: "Whether to include checklist names in release descriptions.")
    var redactChecklists: Bool = false

    mutating func run() throws {
        Internal.initialize()
        parent.definedConfigProperties = defines.reduce(into: [:]) {
            $0[$1.property] = $1.value
        }

        let train = try parent.train?.get()
        let repo = try Internal.openRepo(at: parent.repo)

        let releases: [Release]
        switch show {
        case .all:
            releases = try repo.allReleases(
                allowDirty: false,
                forceLatestVersionTo: nil,
                channel: parent.channel,
                train: train
            )
        case .head:
           guard let release = try repo.latestRelease(
                allowDirty: true,
                untaggedReleaseChannel: parent.channel,
                forceLatestVersionTo: nil,
                train: train
            ) else {
                releases = []
                break
            }

            releases = [release]
        case .latest:
            guard let release = try repo.latestRelease(
                allowDirty: false,
                untaggedReleaseChannel: parent.channel,
                forceLatestVersionTo: nil,
                train: train
            ) else {
                releases = []
                break
            }

            releases = [release]
        // A name has been passed, but it doesn't look like it parses to a version. If it matches a tag prefix in our
        // configuration, and the train hasn't been passed, infer the train from the longest matching prefix.
        case let .tagName(name):
            guard parent.train == nil else {
                throw DescribeReleaseError.tagIsNotAVersion(prefix: nil, name)
            }

            // Future: a more efficient way of doing this, involving pruning/traversing the ingested config in
            // a smarter way
            var prefixLength: Int = 0
            var inferredTrain: Trains.TrainImpl?
            var inferredTagPrefix: String?
            for train in try parent.trains?.get() ?? [] {
                guard let tagPrefix = train.tagPrefix else { continue }
                if name.hasPrefix(tagPrefix),
                   prefixLength < tagPrefix.count {
                    prefixLength = tagPrefix.count
                    inferredTrain = train
                    inferredTagPrefix = tagPrefix
                }
            }

            guard let inferredTagPrefix,
                  let version = Version(name[inferredTagPrefix.endIndex...]) else {
                throw DescribeReleaseError.tagIsNotAVersion(prefix: inferredTagPrefix, name)
            }

            // Re-evaluate the repository configuration according to the release channel and train name.
            let inferredChannel = version.releaseChannel
            parent.channel = inferredChannel
            parent.definedConfigProperties["channel"] = inferredChannel.rawValue
            parent.trainName = inferredTrain?.name

            guard let trains = try Internal.loadTrains(parent.definedConfigProperties) else {
                throw LHCError.configNotFound
            }
            parent.trains = .success(trains)
            
            guard let train = try parent.findTrain() else {
                throw LHCError.configNotFound
            }
            parent.train = .success(train)

            guard let release = try repo.release(exactVersion: version, train: train) else {
                throw DescribeReleaseError.versionNotFound(version: version, train: inferredTrain?.name)
            }

            releases = [release]
        case let .exact(version):
            // Re-evaluate the repository configuration according to the release channel and train name.
            let inferredChannel = version.releaseChannel
            parent.channel = inferredChannel
            parent.definedConfigProperties["channel"] = inferredChannel.rawValue

            guard let trains = try Internal.loadTrains(parent.definedConfigProperties) else {
                throw LHCError.configNotFound
            }
            parent.trains = .success(trains)
            
            guard let train = try parent.findTrain() else {
                throw LHCError.configNotFound
            }
            parent.train = .success(train)

            guard let release = try repo.release(exactVersion: version, train: train) else {
                throw DescribeReleaseError.versionNotFound(version: version, train: parent.trainName)
            }

            releases = [release]
        }

        try show(
            releases: releases,
            repo: repo,
            train: parent.train?.get() // value may have changed from the above step
        )
    }
    
    mutating func show(releases: [Release], repo: Repositoryish, train: Trains.TrainImpl?) throws {
        let result = try parent.show(
            releases: releases,
            format: format,
            includeCommitHashes: !redactCommitHashes,
            includeProjectIds: !redactProjectIds,
            includeChecklists: !redactChecklists
        )

        if let outputPath {
            if outputPath.hasDirectoryPath {
                let plural = show == .all ? "s" : ""
                let descriptionPath = outputPath.appending(path: "release\(plural).\(format.fileExtension)").path(percentEncoded: false)

                let outputPathString = outputPath.absoluteURL.path(percentEncoded: false)
                var isDirectory: Bool?
                if !Internal.fileManager.fileExists(atPath: outputPathString, isDirectory: &isDirectory) {
                    try Internal.fileManager.createDirectory(
                        atPath: outputPathString,
                        withIntermediateDirectories: true
                    )
                }

                if let data = result.data {
                    guard Internal.fileManager
                        .createFile(atPath: descriptionPath, contents: data) else {
                        throw LHCError.invalidPath(descriptionPath)
                    }
                }
                try render(
                    releases: releases,
                    repo: repo,
                    train: train,
                    outputDirectoryPath: outputPathString
                )
            } else if templates.isEmpty {
                if let data = result.data {
                    let path = outputPath.path(percentEncoded: false)
                    guard Internal.fileManager
                        .createFile(atPath: path, contents: data) else {
                        throw LHCError.invalidPath(path)
                    }
                }
            } else {
                throw ValidationError("""
                    Must specify a directory URL (with a trailing slash) when also specifying a template name.
                    """)
            }
        } else {
            if !templates.isEmpty {
                try render(
                    releases: releases,
                    repo: repo,
                    train: train
                )
            }
            if let string = result.string {
                Internal.print(string)
            }
        }
    }

    mutating func render(
        releases: [Release],
        repo: Repositoryish,
        train: Trains.TrainImpl?,
        outputDirectoryPath: String = Internal.fileManager.currentDirectoryPath
    ) throws {
        var isDirectory: Bool?
        guard var templatesDirectory = train?.templatesDirectory else {
            throw ValidationError("Templates directory is not configured.")
        }

        guard Internal.fileManager.fileExists(atPath: templatesDirectory, isDirectory: &isDirectory),
              isDirectory == true else {
            throw ValidationError("""
                Templates path at \(templatesDirectory) \(isDirectory == false ? "is not a directory" : "does not exist")
                """)
        }

        if !templatesDirectory.hasSuffix("/") {
            templatesDirectory.append("/")
        }

        let environment = Stencil.Environment(
            repository: repo,
            train: train,
            urls: [URL(filePath: templatesDirectory)]
        )

        var contents: [String: Data] = [:]
        let oneshot = show != .all // whether or not we should split the output directory up into versions
        if oneshot, let release = releases.first {
            try render(
                release: release,
                in: environment,
                checklistSubdirectoryPath: checklistOutputPath?.path(percentEncoded: false),
                repo: repo,
                train: train
            ).forEach {
                contents["\(outputDirectoryPath)/\($0.key)"] = $0.value
            }
        } else {
            for release in releases {
                try render(
                    release: release,
                    in: environment,
                    checklistSubdirectoryPath: checklistOutputPath?.path(percentEncoded: false),
                    repo: repo,
                    train: train
                ).forEach {
                    contents["\(outputDirectoryPath)/\(release.versionString)/\($0.key)"] = $0.value
                }
            }
        }

        var createdDirectories: Set<String> = []
        for (path, content) in contents {
            let directoryPath = FilePath(path).removingLastComponent().string

            if !directoryPath.isEmpty {
                var isDirectory: Bool? = true
                if createdDirectories.contains(directoryPath) ||
                    Internal.fileManager.fileExists(atPath: directoryPath, isDirectory: &isDirectory) {

                    guard isDirectory == true else {
                        throw POSIXError(.EEXIST)
                    }
                } else {
                    try Internal.fileManager.createDirectory(atPath: directoryPath, withIntermediateDirectories: true)
                    createdDirectories.insert(directoryPath)
                }
            }

            guard Internal.fileManager.createFile(atPath: path, contents: content) else {
                throw LHCError.invalidPath(path)
            }
        }
    }

    mutating func render(
        release: Release,
        in environment: Stencil.Environment,
        checklistSubdirectoryPath: String?,
        repo: Repositoryish,
        train: Trains.TrainImpl?
    ) throws -> [String: Data] {
        var context: [String: Any] = [
            "now": Date(),
            "uuid": UUID().uuidString,
            "release": release,
            "version": release.versionString,
            "short_version": release.shortVersion?.description ?? release.versionString,
            "channel": String(describing: release.version?.releaseChannel ?? .production),
        ]

        if let trainName = release.train {
            context["train"] = trainName

            if let train = try parent.train?.get() {
                let encoder = DictionaryEncoder()
                let dict = try encoder.encode(train)
                context["config"] = dict
            }
        }

        var target: ObjectID?
        if let releaseHash = release.objectHash, let oid = ObjectID(string: releaseHash) {
            target = oid
        } else if show == .head, let oid = try? repo.HEAD().oid {
            target = oid
        }

        if let targetOid = target, let object = try? repo.object(targetOid) {
            context["object"] = object

            if let tag = object as? Tagish, let tagTarget = try? repo.object(tag.target.oid) {
                context["target"] = tagTarget
                target = tagTarget.oid
            } else {
                context["target"] = object
            }
        }

        if let target {
            let tagsByTarget = try repo.tagsByTarget()
            if let otherTags = tagsByTarget[target] {
                context["other_versions"] = otherTags.compactMap {
                    Version(prefix: train?.tagPrefix, versionString: $0.name)
                }.sorted()
            }
        }

        let oidStringLength = (try? ObjectID.minimumLength(
            toLosslesslyRepresent: release.changes.flatMap(\.value).map(\.commitHash),
            initialMinimum: 6
        )) ?? ObjectID.stringLength
        context["oid_string_length"] = oidStringLength

        var contents: [String: Data] = [:]
        if let checklistSubdirectoryPath {
            var checklistNames: [String] = []

            try repo.releaseChecklistContents(
                release: release,
                train: train,
                oidFileNameLength: oidStringLength
            ).forEach {
                contents["\(checklistSubdirectoryPath)/\($0.key)"] = $0.value
                checklistNames.append($0.key)
            }

            context["checklist_filenames"] = checklistNames
        }

        // Make sure we don't render the same template multiple times, it's unnecessary (and the dictionary merging
        // step after this will crash otherwise)
        var seenTemplates = Set<String>()
        var uniqueTemplates: [String] = []
        for template in templates {
            guard !seenTemplates.contains(template) else { continue }
            uniqueTemplates.append(template)
            seenTemplates.insert(template)
        }
        templates = uniqueTemplates

        for template in templates {
            let renderedTemplateContents = try environment.renderRelease(
                templateName: template,
                release: release,
                additionalContext: context
            )
            contents = contents.merging(
                renderedTemplateContents,
                uniquingKeysWith: { lhs, rhs in
                    assertionFailure("filename collision: \(lhs) and \(rhs) for the same key")
                    return rhs
                }
            )
        }

        return contents
    }

    
    func recursivelyCreateFilesAndDirectories(_ contents: [String: Data]) throws {
        var createdDirectories = Set<String>()
        for (path, fileContents) in contents {
            func createFile() throws {
                guard Internal.fileManager.createFile(atPath: path, contents: fileContents) else {
                    throw LHCError.invalidPath(path)
                }
            }

            guard let lastSlash = path.lastIndex(of: "/") else {
                try createFile()
                continue
            }

            let directory = String(path[path.startIndex..<lastSlash])
            guard !createdDirectories.contains(directory) else {
                try createFile()
                continue
            }

            let directoryComponents = directory.split(separator: "/")
            for index in 1...directoryComponents.count {
                let parent = "/" + directoryComponents[0..<index].joined(separator: "/")

                guard !createdDirectories.contains(where: { $0.hasPrefix(parent) }) else { continue }

                var isDirectory: Bool? = false
                guard !Internal.fileManager.fileExists(atPath: parent, isDirectory: &isDirectory) else {
                    guard isDirectory == true else {
                        throw POSIXError(.EEXIST)
                    }

                    createdDirectories.insert(parent) // so we don't hit the filesystem repeatedly for this path
                    continue
                }

                try Internal.fileManager.createDirectory(atPath: parent, withIntermediateDirectories: false)
                createdDirectories.insert(parent)
            }

            try createFile()
        }
    }
}

enum OutputSpec: Equatable, ExpressibleByArgument {
    case all
    case head
    case latest
    case exact(version: Version)
    case tagName(String)

    init?(argument: String) {
        switch argument {
        case "all":
            self = .all
        case "head", "HEAD":
            self = .head
        case "latest":
            self = .latest
        default:
            if let version = Version(argument) {
                self = .exact(version: version)
            } else {
                self = .tagName(argument)
            }
        }
    }
}

enum DescribeReleaseError: Error, CustomStringConvertible {
    case emptyRelease(from: TagReferenceish, to: ObjectID)
    case versionNotFound(version: Version, train: String?)
    case tagIsNotAVersion(prefix: String?, String)

    var description: String {
        switch self {
        case let .emptyRelease(tag, leaf):
            return "Not creating new release: no commits exist from tag '\(tag.name)' to commit '\(leaf)'"
        case let .versionNotFound(version, train):
            var result = "No version \(version) found in commit history"
            if let releaseTrain = train {
                result += " for train '\(releaseTrain)'"
            }
            return result
        case let .tagIsNotAVersion(prefix, string):
            var result = "'\(string)' is not a valid version"
            if let prefix {
                result += " in '\(prefix)\(string)'"
            }
            return result
        }
    }
}
