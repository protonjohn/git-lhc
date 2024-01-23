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
        parent.commandConfigDefines = defines.reduce(into: [:]) {
            $0[$1.property] = $1.value
        }

        var options = try parent.options?.get()

        let repo = try Internal.openRepo(at: parent.repo)

        let releases: [Release]
        switch show {
        case .all:
            releases = try repo.allReleases(
                allowDirty: false,
                forceLatestVersionTo: nil,
                channel: parent.channel,
                options: options
            )
        case .head:
           guard let release = try repo.latestRelease(
                allowDirty: true,
                untaggedReleaseChannel: parent.channel,
                forceLatestVersionTo: nil,
                options: options
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
                options: options
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
            var inferredTrain: String?
            var inferredTagPrefix: String?
            for (train, options) in try parent.allTrainOptions() {
                guard let tagPrefix = options.tagPrefix else { continue }
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

            let inferredChannel = version.releaseChannel
            parent.channel = inferredChannel
            parent.train = inferredTrain

            // Re-evaluate the repository configuration according to the release channel and train name.
            let newConfig = try? parent.config?.get().eval(
                train: inferredTrain,
                channel: inferredChannel,
                define: parent.commandConfigDefines
            )
            options = try? newConfig?.options
            parent.evaluatedConfig = newConfig.map(Result.success)
            parent.options = options.map(Result.success)

            guard let release = try repo.release(exactVersion: version, options: options) else {
                throw DescribeReleaseError.versionNotFound(version: version, train: inferredTrain)
            }

            releases = [release]
        case let .exact(version):
            let inferredChannel = version.releaseChannel
            parent.channel = inferredChannel

            let newConfig = try? parent.config?.get().eval(
                train: parent.train,
                channel: inferredChannel,
                define: parent.commandConfigDefines
            )
            options = try? newConfig?.options
            parent.evaluatedConfig = newConfig.map(Result.success)
            parent.options = options.map(Result.success)

            guard let release = try repo.release(exactVersion: version, options: options) else {
                throw DescribeReleaseError.versionNotFound(version: version, train: parent.train)
            }

            releases = [release]
        }

        try show(releases: releases, repo: repo, options: options)
    }
    
    mutating func show(releases: [Release], repo: Repositoryish, options: Configuration.Options?) throws {
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
                let descriptionPath = outputPath.appending(path: "release\(plural).\(format.fileExtension)").path()
                if let data = result.data {
                    guard Internal.fileManager
                        .createFile(atPath: descriptionPath, contents: data) else {
                        throw LHCError.invalidPath(descriptionPath)
                    }
                }
                try render(releases: releases, repo: repo, options: options, outputDirectoryPath: outputPath.path())
            } else if templates.isEmpty {
                if let data = result.data {
                    let path = outputPath.path()
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
                try render(releases: releases, repo: repo, options: options)
            }
            if let string = result.string {
                Internal.print(string)
            }
        }
    }

    mutating func render(
        releases: [Release],
        repo: Repositoryish,
        options: Configuration.Options?,
        outputDirectoryPath: String = Internal.fileManager.currentDirectoryPath
    ) throws {
        var isDirectory: Bool?
        guard var templatesDirectory = options?.templatesDir,
              Internal.fileManager.fileExists(atPath: templatesDirectory, isDirectory: &isDirectory),
              isDirectory == true else {
            throw ValidationError("""
                Templates directory is either not configured, does not exist, or is not a directory.
                """)
        }

        if !templatesDirectory.hasSuffix("/") {
            templatesDirectory.append("/")
        }

        let environment = Stencil.Environment(
            repository: repo,
            options: options,
            urls: [URL(filePath: templatesDirectory)]
        )

        var contents: [String: Data] = [:]
        let oneshot = show != .all // whether or not we should split the output directory up into versions
        if oneshot, let release = releases.first {
            try render(
                release: release,
                in: environment,
                checklistSubdirectoryPath: checklistOutputPath?.path(),
                repo: repo,
                options: options
            ).forEach {
                contents["\(outputDirectoryPath)/\($0.key)"] = $0.value
            }
        } else {
            for release in releases {
                try render(
                    release: release,
                    in: environment,
                    checklistSubdirectoryPath: checklistOutputPath?.path(),
                    repo: repo,
                    options: options
                ).forEach {
                    contents["\(outputDirectoryPath)/\(release.versionString)/\($0.key)"] = $0.value
                }
            }
        }

        var createdDirectories = Set<String>()
        for (path, fileContents) in contents {
            defer {
                _ = Internal.fileManager.createFile(atPath: path, contents: fileContents)
            }

            guard let lastSlash = path.lastIndex(of: "/") else { continue }
            let directory = String(path[path.startIndex..<lastSlash])
            guard !createdDirectories.contains(directory) else { continue }

            let directoryComponents = directory.split(separator: "/")
            for index in 1...directoryComponents.count {
                let parent = "/" + directoryComponents[0..<index].joined(separator: "/")

                guard !createdDirectories.contains(where: { $0.hasPrefix(parent) }) else { continue }

                var isDirectory: Bool? = false
                guard !Internal.fileManager.fileExists(atPath: parent, isDirectory: &isDirectory) else {
                    guard isDirectory == true else {
                        throw POSIXError(.EEXIST)
                    }
                    continue
                }

                try Internal.fileManager.createDirectory(atPath: parent, withIntermediateDirectories: false)
                createdDirectories.insert(parent)
            }
        }
    }

    mutating func render(
        release: Release,
        in environment: Stencil.Environment,
        checklistSubdirectoryPath: String?,
        repo: Repositoryish,
        options: Configuration.Options?
    ) throws -> [String: Data] {
        var context: [String: Any] = [
            "release": release,
            "version": release.versionString,
            "short_version": release.shortVersion?.description ?? release.versionString
        ]

        if let train = release.train {
            context["train"] = train
        }

        if let evaluatedConfig = try parent.evaluatedConfig?.get() {
            context["config"] = evaluatedConfig.jsonDict
        }

        var target: ObjectID?
        if let releaseHash = release.objectHash, let oid = ObjectID(string: releaseHash) {
            target = oid
        } else if show == .head, let oid = try? repo.HEAD().oid {
            target = oid
        }

        if let target {
            context["object"] = try? repo.object(target)
        }

        let oidStringLength = try ObjectID.minimumLength(
            toLosslesslyRepresent: release.changes.flatMap(\.value).map(\.commitHash),
            initialMinimum: 6
        )
        context["oid_string_length"] = oidStringLength

        var contents: [String: Data] = [:]
        if let checklistSubdirectoryPath {
            var checklistNames: [String] = []

            try repo.releaseChecklistContents(
                release: release,
                options: options,
                oidFileNameLength: oidStringLength
            ).forEach {
                contents["\(checklistSubdirectoryPath)/\($0.key)"] = $0.value
                checklistNames.append($0.key)
            }

            context["checklist_filenames"] = checklistNames
        }

        for template in templates {
            contents = contents.merging(
                try environment.renderRelease(
                    templateName: template,
                    release: release,
                    additionalContext: context
                ),
                uniquingKeysWith: { lhs, rhs in
                    assertionFailure("filename collision: \(lhs) and \(rhs) for the same key")
                    return rhs
                }
            )
        }

        return contents
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
        case "head":
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
