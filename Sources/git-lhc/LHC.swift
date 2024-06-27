//
//  Main.swift
//
//  Created by John Biggs on 06.10.23.
//

import Foundation
import ArgumentParser
import Version
import SwiftGit2
import LHC
import LHCInternal
import DictionaryCoder

@main
public struct LHC: AsyncParsableCommand {
    public static var configuration = CommandConfiguration(
        commandName: "git-lhc",
        abstract: "A tool for git repositories that use conventional commits and semantic versioning.",
        subcommands: [
            Attr.self,
            Check.self,
            Lint.self,
            Describe.self,
            New.self,
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

        lazy var trainName: String? = {
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

        /// This should always get set (if needed) before evaluating `trains`, since `trains` is a lazy variable.
        /// Sometimes you may need to 
        var definedConfigProperties: [String: String] = [:]
        lazy var trains: Result<[Trains.TrainImpl], Error>? = {
            do {
                if definedConfigProperties["channel"] == nil {
                    definedConfigProperties["channel"] = channel.rawValue
                }

                guard let trains = try Internal.loadTrains(definedConfigProperties) else {
                    return nil
                }

                return .success(trains)
            } catch {
                return .failure(error)
            }
        }()

        mutating func findTrain() throws -> Trains.TrainImpl? {
            guard let _trains = self.trains else { return nil }
            let trains = try _trains.get()
            guard trains.count > 1 else { return trains.first }
            guard let train = trains.first(where: { $0.name == trainName }) else {
                return nil
            }
            return train
        }

        /// The options generated from the configuration file with the above train and channel applied.
        lazy var train: Result<Trains.TrainImpl, Error>? = {
            do {
                guard let train = try findTrain() else {
                    return nil
                }
                return .success(train)
            } catch {
                return .failure(error)
            }
        }()

        /// Gets the version from CI if it is set.
        lazy var forcedVersion: Version? = {
            guard let tagName = Internal.tagName else {
                return nil
            }

            return Version(prefix: try? train?.get().tagPrefix, versionString: tagName)
        }()

        mutating func show(
            releases: [Release],
            format: ReleaseFormat,
            includeCommitHashes: Bool,
            includeProjectIds: Bool,
            includeChecklists: Bool
        ) throws -> StringOrData {
            let train = try? train?.get()
            var encodedValue = releases

            if !includeCommitHashes || !includeProjectIds {
                encodedValue = encodedValue.map {
                    $0.redacting(
                        commitHashes: !includeCommitHashes,
                        projectIds: !includeProjectIds,
                        checklists: !includeChecklists  
                    )
                }
            }

            let result: StringOrData

            switch format {
            case .json:
                let encoder = JSONEncoder()
                result = try .init(encoder.encode(encodedValue))
            case .plist:
                let encoder = PropertyListEncoder()
                result = try .init(encoder.encode(encodedValue))
            case .text:
                let description = encodedValue
                    .compactMap { $0.describe(train: train) }.joined(separator: "\n") + "\n"
                result = .init(description)
            case .version:
                let description = encodedValue
                    .compactMap { $0.versionString }.joined(separator: "\n") + "\n"
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

    struct Define {
        public let property: String
        public let value: String
    }

    public init() {
    }
}

extension LHC {
    static func sign(
        _ contents: Data,
        options: SigningOptions,
        completionHandler: @escaping (Result<Data?, Error>) -> ()
    ) {
        Task.detached {
            do {
                let signingCommand = options.signingCommand
                let status = Pipe()
                let input = Pipe()
                let output = Pipe()

                try input.fileHandleForWriting.write(contentsOf: contents)
                try input.fileHandleForWriting.close()

                for await event in try Internal.shell.run(
                    command: signingCommand,
                    ttyEnvironmentVariable: "GPG_TTY",
                    extraFileDescriptors: [
                        SigningOptions.statusDescriptor: status.fileHandleForWriting,
                        SigningOptions.inputDescriptor: input.fileHandleForReading,
                        SigningOptions.outputDescriptor: output.fileHandleForWriting
                    ]
                ) {
                    guard case .exit(let code) = try event.get() else {
                        continue
                    }

                    guard code == 0 else {
                        throw Shell.Exit(rawValue: code)
                    }

                    break
                }

                // Close the symmetric end of the pipe so the read will complete
                try output.fileHandleForWriting.close()
                let data = try output.fileHandleForReading.readToEnd()
                completionHandler(.success(data))
            } catch {
                completionHandler(.failure(error))
            }
        }
    }

    @available(*, noasync, message: "This function is not available from an async context.")
    static func sign(_ contents: Data, options: SigningOptions) throws -> Data? {
        var result: Result<Data?, Error>?

        let group = DispatchGroup()
        group.enter()
        sign(contents, options: options) {
            result = $0
            group.leave()
        }
        group.wait()

        let value = try result?.get()
        return value
    }
}

extension ConventionalCommit.Trailer: ExpressibleByArgument {
    public init?(argument: String) {
        let components = argument.split(separator: "=", maxSplits: 1)

        let key = String(components.first!)
        let value = components.count > 1 ? String(components[1]) : "true"

        guard let (_, trailers) = try? Self.trailers(from: "\(key): \(value)"),
              !trailers.isEmpty else { return nil }

        self = trailers.first!
    }
}

extension LHC.Define: ExpressibleByArgument {
    init?(argument: String) {
        let components = argument.split(separator: "=", maxSplits: 1)

        self.init(
            property: String(components.first!),
            value: components.count > 1 ? String(components[1]) : "YES"
        )
    }
}

enum LHCError: Error, CustomStringConvertible {
    case invalidPath(String)
    case configNotFound

    var description: String {
        switch self {
        case let .invalidPath(path):
            return "Invalid path '\(path)'."
        case .configNotFound:
            return "Configuration file not found at \(LHCEnvironment.configFilePath.value!)"
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

extension ReleaseChannel: ExpressibleByArgument {
}

extension ReleaseFormat: ExpressibleByArgument {
}

extension ExpressibleByArgument where Self: CaseIterable & RawRepresentable, RawValue == String {
    static var possibleValues: String { allCases.map(\.rawValue).humanReadableDelineatedString }
}
