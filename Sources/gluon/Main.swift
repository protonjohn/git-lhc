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
        subcommands: [
            Lint.self,
            Changelog.self,
            CreateRelease.self,
            FindVersions.self,
            CreateDefaultConfig.self,
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

    static var tagName: String? {
        GitlabEnvironment.commitTag.value
    }
}

extension Gluon {
    static var readPassphrase: (() -> String?) = {
        var buf = [CChar](repeating: 0, count: 8192)
        guard let passphraseBytes = readpassphrase("Enter passphrase: ", &buf, buf.count, 0) else {
            return nil
        }
        return String(cString: passphraseBytes)
    }

    static var promptUser: ((String) -> String?) = {
        Self.print($0, terminator: "")
        return readLine(strippingNewline: true)
    }

    static func promptForContinuation(_ prompt: String, defaultAction: Bool = true) -> Bool {
        let action = defaultAction ? "Y/n" : "y/N"
        var prompt = "\(prompt) Continue? (\(action)) "

        repeat {
            guard let string = Self.promptUser(prompt) else {
                Gluon.print("Encountered unexpected EOF.")
                return false
            }

            guard !string.isEmpty else {
                return defaultAction
            }

            guard let result = Bool(promptString: string) else {
                prompt = "Unknown response '\(string)'. Continue \(action): "
                continue
            }

            return result
        } while true
    }
}
