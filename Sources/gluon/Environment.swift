//
//  Environment.swift
//  
//
//  Created by John Biggs on 10.10.23.
//

import Foundation
import Version

protocol EnvironmentVariable {
    var key: String { get }
    var defaultValue: String? { get }
}

extension EnvironmentVariable where Self: RawRepresentable, RawValue == String {
    var key: String { rawValue }
}

extension EnvironmentVariable {
    var value: String? {
        Gluon.processInfo.environment[key] ?? defaultValue
    }
}

enum XcodeEnvironment: String, EnvironmentVariable {
    case srcRoot = "SRCROOT"

    var defaultValue: String? {
        switch self {
        case .srcRoot:
            return Gluon.fileManager.currentDirectoryPath
        }
    }
}

enum GitlabEnvironment: String, EnvironmentVariable {
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

    var defaultValue: String? { nil }

    static var isCI: Bool {
        Self.CI.value != nil
    }
}

enum GluonEnvironment: String, EnvironmentVariable {
    case configFilePath = "GLUON_CONFIG_PATH"
    case trainName = "GLUON_TRAIN_NAME"

    var defaultValue: String? {
        switch self {
        case .configFilePath:
            return Gluon.fileManager.traverseUpwardsUntilFinding(fileName: ".gluon.yml")
        case .trainName:
            return nil
        }
    }
}

extension Configuration.Train {
    static var environment: Self? {
        guard let trainName = GluonEnvironment.trainName.value else { return nil }
        do {
            return try Configuration.train(named: trainName)
        } catch {
            Gluon.print(error, error: true)
            return nil
        }
    }
}

extension Version {
    static var environment: Self? {
        guard let tagName = GitlabEnvironment.commitTag.value else { return nil }
        let tagPrefix = Configuration.Train.environment?.tagPrefix

        return Version(prefix: tagPrefix, versionString: tagName)
    }
}
