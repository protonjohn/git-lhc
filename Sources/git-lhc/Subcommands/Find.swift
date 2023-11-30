//
//  FindVersions.swift
//  
//
//  Created by John Biggs on 26.10.23.
//

import Foundation
import ArgumentParser
import SwiftGit2
import LHC
import LHCInternal

struct Find: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Find releases that introduced a commit with the given task ID(s)."
    )

    @OptionGroup()
    var parent: LHC.Options

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
        Internal.initialize()

        // First, add the project prefix to IDs that parse as Ints, if we have one defined.
        if let prefix = parent.options?.projectIdPrefix {
            taskIds = taskIds.map {
                guard Int($0) == nil else {
                    return prefix + $0
                }
                return $0
            }
        }

        let trailerName = parent.options?.projectIdTrailerName
        let repo = try Internal.openRepo(at: parent.repo)

        let taskIdSet = Set(taskIds)
        let releases = try parent.allTrainOptions().flatMap { (keypair: (String?, Configuration.Options)) -> [Release] in
            let (_, options) = keypair
            return try repo.allReleases(
                allowDirty: true,
                forceLatestVersionTo: nil,
                options: options
            ).filter { release in
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
            Internal.print("No releases with the specified task ID\(taskIds.count > 1 ? "s" : "") were found.")
            throw ExitCode(1)
        }

        try show(releases: releases)
    }

    mutating func show(releases: [Release]) throws {
        let result = try parent.show(
            releases: releases,
            format: format,
            includeCommitHashes: true,
            includeProjectIds: true
        )

        if let outputPath = output?.path(), let data = result.data {
            guard Internal.fileManager
                .createFile(atPath: outputPath, contents: data) else {
                throw LHCError.invalidPath(outputPath)
            }
        } else if let string = result.string {
            Internal.print(string)
        }
    }
}
