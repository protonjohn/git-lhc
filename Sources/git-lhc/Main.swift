//
//  Main.swift
//
//  Created by John Biggs on 06.10.23.
//

import Foundation
import ArgumentParser
import Version
import Yams
import SwiftGit2
import LHC
import LHCInternal

@main
struct LHC: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "git-lhc",
        abstract: "A tool for git repositories that use conventional commits and semantic versioning.",
        subcommands: [
            Config.self,
            Attr.self,
            Lint.self,
            Describe.self,
            CreateRelease.self,
            Find.self,
            Embed.self,
        ]
    )

    struct Options: ParsableArguments {
        @Option(
            name: .shortAndLong,
            help: .init(
                "The path to the repository.",
                discussion: """
                If not specified, LHC will traverse upwards until it finds a directory or filename called `.git`, and
                then use that as the repository URL.

                All items passed to LHC with relative paths will be resolved relative to the repository root.
                """
            )
        )
        var repo: String = Internal.repoPath

        @Option(
            name: [.customShort("t"), .customLong("train")],
            help: .init(
                "An optional train to supply for configuration.",
                discussion: """
                If train is supplied, the build config will be evaluated with the appropriate value defined.
                """
            )
        )
        var commandLineTrain: String?

        @Option(
            name: .shortAndLong,
            help: "An optional channel to supply for configuration. Possible values are \(ReleaseChannel.possibleValues)."
        )
        var channel: ReleaseChannel = .environment ?? .production

        lazy var train: String? = {
            commandLineTrain ?? LHCEnvironment.trainName.value
        }()

        /// The git configuration object for the repository.
        lazy var gitConfig: Result<any Configish, Error>? = {
            do {
                let repo = try Internal.openRepo(at: repo)
                return try .success(repo.config)
            } catch {
                return .failure(error)
            }
        }()

        /// The parsed and ingested configuration file.
        lazy var config: Result<Configuration.IngestedConfig, Error>? = {
            guard let config = Configuration.getConfig(repo) else {
                self.config = nil
                self.options = nil
                return nil
            }

            do {
                return try .success(config.get().ingest())
            } catch {
                return .failure(error)
            }
        }()

        /// The options generated from the configuration file with the above train and channel applied.
        lazy var options: Result<Configuration.Options, Error>? = {
            guard let config else { return nil }

            do {
                return try .success(config.get().eval(train: train, channel: channel).options)
            } catch {
                return .failure(error)
            }
        }()

        /// Gets the version from CI if it is set.
        lazy var forcedVersion: Version? = {
            guard let tagName = Internal.tagName else {
                return nil
            }

            return Version(prefix: try? options?.get().tagPrefix, versionString: tagName)
        }()

        mutating func allTrainOptions() throws -> [String?: Configuration.Options] {
            guard let options = try? options?.get() else { return [:] }
            guard let train = options.train else { return [nil: options] }
            guard var trains = options.trains else { return [train: options] }

            var result: [String: Configuration.Options] = [:]
            if let train = options.train {
                // If we already have a train specified at the moment, then options has already been evaluated for the
                // current train, so save the current result.
                result[train] = options
                trains.removeAll { $0 == train }
            }

            for train in trains {
                result[train] = try? config?.get().eval(train: train, channel: channel).options
            }

            return result
        }

        mutating func show(
            releases: [Release],
            format: ReleaseFormat,
            includeCommitHashes: Bool,
            includeProjectIds: Bool
        ) throws -> StringOrData {
            let options = try? options?.get()
            var encodedValue = releases

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
                let description = encodedValue.compactMap { $0.describe(options: options) }.joined(separator: "\n")
                result = .init(description)
            }

            return result
        }

        mutating func signingOptions() throws -> SigningOptions? {
            let `default` = Internal.defaultGitConfig
            let local = try gitConfig?.get()
            let global = (try? local?.global) ?? (try? `default`?.global)
            let signingOptions = local?.signingOptions ?? global?.signingOptions ?? `default`?.signingOptions
            return signingOptions
        }
    }

    struct Define: ExpressibleByArgument {
        public let property: Configuration.Property
        public let value: String
    }
}

extension LHC {
    static func sign(_ contents: String, options: SigningOptions) throws -> String {
        let signingCommand = options.signingCommand.joined(separator: " ")

        guard let output = try Internal.spawnAndWaitWithOutput(command: signingCommand, input: contents) else {
            return ""
        }
        return String(data: output, encoding: .utf8) ?? ""
    }
}

extension ConventionalCommit.Trailer: ExpressibleByArgument {
    public init?(argument: String) {
        let components = argument.split(separator: "=", maxSplits: 1)

        let key = String(components.first!)
        let value = components.count > 1 ? String(components[1]) : "true"
        guard let trailer = Self(parsing: "\(key): \(value)") else {
            return nil
        }
        self = trailer
    }
}

extension LHC.Define {
    init?(argument: String) {
        let components = argument.split(separator: "=", maxSplits: 1)

        self.init(
            property: .init(rawValue: String(components.first!)),
            value: components.count > 1 ? String(components[1]) : "YES"
        )
    }
}

enum LHCError: Error, CustomStringConvertible {
    case invalidPath(String)

    var description: String {
        switch self {
        case let .invalidPath(path):
            return "Invalid path '\(path)'."
        }
    }
}

extension URL {
    public static func createFromPathOrThrow(_ path: String) throws -> Self {
        guard let url = Self(string: path) else {
            throw LHCError.invalidPath(path)
        }
        return url
    }
}
