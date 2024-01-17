//
//  Environment.swift
//  
//
//  Created by John Biggs on 10.10.23.
//

import Foundation
import Version

public protocol EnvironmentVariable {
    var key: String { get }
    var defaultValue: String? { get }
}

extension EnvironmentVariable where Self: RawRepresentable, RawValue == String {
    public var key: String { rawValue }
}

extension EnvironmentVariable {
    public var value: String? {
        Internal.processInfo.environment[key] ?? defaultValue
    }
}

public enum XcodeEnvironment: String, EnvironmentVariable {
    case srcRoot = "SRCROOT"

    public var defaultValue: String? {
        switch self {
        case .srcRoot:
            return Internal.fileManager.currentDirectoryPath
        }
    }
}

public enum GitlabEnvironment: String, EnvironmentVariable {
    case CI = "CI"
    case isManualJob = "CI_JOB_MANUAL"

    case jobURL = "CI_JOB_URL"
    case commitTag = "CI_COMMIT_TAG"
    case commitSha = "CI_COMMIT_SHA"
    case commitBranch = "CI_COMMIT_BRANCH"
    case defaultBranch = "CI_DEFAULT_BRANCH"
    case commitBeforeChange = "CI_COMMIT_BEFORE_SHA"
    case mergeRequestDiffBaseSha = "CI_MERGE_REQUEST_DIFF_BASE_SHA"
    case mergeRequestSourceBranch = "CI_MERGE_REQUEST_SOURCE_BRANCH_NAME"

    public var defaultValue: String? { nil }
}

public enum LHCEnvironment: String, EnvironmentVariable {
    case configFilePath = "LHC_CONFIG_PATH"
    case trainName = "LHC_TRAIN_NAME"
    case channel = "LHC_RELEASE_CHANNEL"
    case previousChecklistResult = "LHC_CHECK_PREVIOUS"
    case jiraApiToken = "LHC_JIRA_APITOKEN"
    case jiraUsername = "LHC_JIRA_USERNAME"
    case jiraEndpoint = "LHC_JIRA_ENDPOINT"

    public var defaultValue: String? {
        guard case .configFilePath = self else {
            return nil
        }
        
        return Internal.fileManager.traverseUpwardsUntilFinding(fileName: ".lhc")
    }
}

public enum UNIXEnvironment: String, EnvironmentVariable {
    case editor = "EDITOR"

    public var defaultValue: String? {
        switch self {
        case .editor:
            return "/usr/bin/nano"
        }
    }
}
