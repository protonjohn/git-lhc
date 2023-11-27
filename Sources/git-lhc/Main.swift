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
struct LHC: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        abstract: "An integration tool for easier cross-team collaboration.",
        subcommands: [
            Lint.self,
            DescribeRelease.self,
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
            guard let path = LHC.fileManager.traverseUpwardsUntilFinding(fileName: ".git", isDirectory: nil) else {
                return LHC.fileManager.currentDirectoryPath
            }

            let url = URL(filePath: path)
            var result = url.deletingLastPathComponent().path()
            while result.hasSuffix("/") {
                result.removeLast()
            }

            return result
        }()
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

/// Values based on configuration variables.
extension LHC {
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
        LHCEnvironment.configFilePath.value
    }

    static var branchName: String? {
        GitlabEnvironment.mergeRequestSourceBranch.value ??
            GitlabEnvironment.commitBranch.value
    }

    static var tagName: String? {
        GitlabEnvironment.commitTag.value
    }

    static var editor: String {
        guard let result = UNIXEnvironment.editor.value else {
            fatalError("No editor set in environment")
        }
        return result
    }
}

extension LHC {
    static var spawnProcessAndWaitForTermination: ((URL, [String]) throws -> ()) = { url, arguments in
        let task = Process()
        task.executableURL = url
        task.arguments = arguments
        task.environment = LHC.processInfo.environment

        task.standardInput = FileHandle(forReadingAtPath: "/dev/tty")
        task.standardError = FileHandle(forWritingAtPath: "/dev/tty")
        task.standardOutput = FileHandle(forWritingAtPath: "/dev/tty")

        try task.run()
        // Note: this is pure wizardry but is absolutely key to making spawn work properly
        tcsetpgrp(STDIN_FILENO, task.processIdentifier)

        task.waitUntilExit()
    }

    static func spawnAndWait(executableURL: URL, arguments: [String]) throws {
        try spawnProcessAndWaitForTermination(executableURL, arguments)
    }
}
