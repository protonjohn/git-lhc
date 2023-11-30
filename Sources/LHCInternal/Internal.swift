//
//  Internal.swift
//  
//
//  Created by John Biggs on 29.11.23.
//

import Foundation
import SwiftGit2

public enum Internal {
    public static func initialize() {
        SwiftGit2.initialize()
    }

    public static var isCI: Bool {
        GitlabEnvironment.CI.value != nil
    }

    public static var isManualJob: Bool {
        GitlabEnvironment.isManualJob.value == "true"
    }

    public static var jobURL: URL? {
        guard let value = GitlabEnvironment.jobURL.value else {
            return nil
        }
        return URL(string: value)
    }

    public static var srcRoot: String? {
        XcodeEnvironment.srcRoot.value
    }

    public static var configFilePath: String? {
        LHCEnvironment.configFilePath.value
    }

    public static var branchName: String? {
        GitlabEnvironment.mergeRequestSourceBranch.value ??
            GitlabEnvironment.commitBranch.value
    }

    public static var tagName: String? {
        GitlabEnvironment.commitTag.value
    }

    public static var editor: String {
        guard let result = UNIXEnvironment.editor.value else {
            fatalError("No editor set in environment")
        }
        return result
    }

    public static var repoPath: String {
        guard let path = Internal.fileManager.traverseUpwardsUntilFinding(fileName: ".git", isDirectory: nil) else {
            return Internal.fileManager.currentDirectoryPath
        }

        let url = URL(filePath: path)
        var result = url.deletingLastPathComponent().path()
        while result.hasSuffix("/") {
            result.removeLast()
        }

        return result
    }
}
