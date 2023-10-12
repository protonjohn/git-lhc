//
//  Main.swift
//
//  Created by John Biggs on 06.10.23.
//

import Foundation
import ArgumentParser
import Yams
import SwiftGit2

@main
struct Gluon: ParsableCommand {
    static var configuration = CommandConfiguration(
        subcommands: [
            Lint.self,
            Changelog.self,
            CreateDefaultConfig.self,
            TagRelease.self,
        ]
    )

    struct Options: ParsableArguments {
        @Option(help: "The path to the repository.")
        var repo: String = Gluon.fileManager.currentDirectoryPath
    }
}

enum GluonError: Error, CustomStringConvertible {
    case invalidPath(String)

    var description: String {
        switch self {
        case let .invalidPath(path):
            return "Invalid path '\(path)'."
        }
    }
}

/// Values based on configuration variables.
extension Gluon {
    static var isCI: Bool {
        GitlabEnvironment.CI.value == "true"
    }

    static var isManualJob: Bool {
        GitlabEnvironment.isManualJob.value == "true"
    }

    static var jobURL: URL? {
        guard let value = GitlabEnvironment.jobURL.value else {
            return nil
        }
        return URL(string: value)
    }

    static var srcRoot: String? {
        XcodeEnvironment.srcRoot.value
    }

    static var configFilePath: String? {
        GluonEnvironment.configFilePath.value
    }

    static var branchName: String? {
        GitlabEnvironment.mergeRequestSourceBranch.value ??
            GitlabEnvironment.commitBranch.value
    }
}

extension Gluon {
    static func openRepo(at path: String) throws -> Repositoryish {
        guard let url = URL(string: path) else {
            throw GluonError.invalidPath(path)
        }

        return try Self.openRepo(url).get()
    }
}
