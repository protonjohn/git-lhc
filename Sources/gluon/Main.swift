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

@main
struct Gluon: ParsableCommand {
    static var configuration = CommandConfiguration(
        abstract: "An integration tool for easier cross-team collaboration.",
        subcommands: [
            Lint.self,
            Changelog.self,
            CreateRelease.self,
            FindVersions.self,
            ReplaceVersions.self,
            CreateDefaultConfig.self,
        ]
    )

    struct Options: ParsableArguments {
        @Option(
            name: .shortAndLong,
            help: "The path to the repository."
        )
        var repo: String = {
            guard let path = Gluon.fileManager.traverseUpwardsUntilFinding(fileName: ".git", isDirectory: true),
                  let url = URL(string: path) else {
                return Gluon.fileManager.currentDirectoryPath
            }

            var result = url.deletingLastPathComponent().path()
            while result.hasSuffix("/") {
                result.removeLast()
            }

            return result
        }()
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

    static var tagName: String? {
        GitlabEnvironment.commitTag.value
    }
}
