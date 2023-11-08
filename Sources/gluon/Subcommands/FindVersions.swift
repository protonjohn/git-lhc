//
//  FindVersions.swift
//  
//
//  Created by John Biggs on 26.10.23.
//

import Foundation
import ArgumentParser
import SwiftGit2

struct FindVersions: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Find releases that introduced a commit with the given task ID(s)."
    )

    @OptionGroup()
    var parent: Gluon.Options

    @Option(
        name: .shortAndLong,
        help: "Which trains to search for versions in. If any trains are configured, defaults to looking in all of them.",
        transform: Configuration.train(named:)
    )
    var train: Configuration.Train? = .environment

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

    @Argument()
    var taskIds: [String]

    mutating func run() throws {
        SwiftGit2.initialize()

        // First, add the project prefix to IDs that parse as Ints, if we have one defined.
        if let prefix = Configuration.configuration.projectPrefix {
            taskIds = taskIds.map {
                guard Int($0) == nil else {
                    return prefix + $0
                }
                return $0
            }
        }

        let trailerName = Configuration.configuration.projectIdTrailerName
        let repo = try Gluon.openRepo(at: parent.repo)

        let trains: [Configuration.Train?]
        if let train {
            trains = [train]
        } else {
            trains = (Configuration.configuration.trains ?? []) + [nil]
        }

        let taskIdSet = Set(taskIds)
        let releases = try trains.flatMap { (train: Configuration.Train?) -> [Release] in
            try repo.allReleases(
                for: train,
                allowDirty: true,
                untaggedPrereleaseChannel: nil,
                forceLatestVersionTo: nil
            ).filter { release in
                print(release)
                // If a trailer name is set in the configuration, look for trailers first.
                if trailerName != nil {
                    let releaseProjectIds = release.changes.flatMap { $0.value.flatMap(\.projectIds) }
                    if !taskIdSet.isDisjoint(with: releaseProjectIds) {
                        return true
                    }
                }

                // Otherwise, see if the task ID is mentioned in the change summary.
                for taskId in taskIds {
                    for change in release.changes.flatMap({ $0.value }) {
                        if change.summary.contains(taskId) {
                            return true
                        }
                    }
                }

                return false
            }
        }

        guard !releases.isEmpty else {
            Gluon.print("No releases with the specified task ID\(taskIds.count > 1 ? "s" : "") were found.")
            throw ExitCode(1)
        }

        try show(releases: releases)
    }

    func show(releases: [Release]) throws {
        let result = try releases.show(format, includeCommitHashes: true, includeProjectIds: true)

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
