//
//  EnvVars.swift
//  
//
//  Created by John Biggs on 10.10.23.
//

import Foundation

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
    case commitBranch = "CI_COMMIT_BRANCH"
    case mergeRequestSourceBranch = "CI_MERGE_REQUEST_SOURCE_BRANCH_NAME"

    var defaultValue: String? {
        switch self {
        default:
            return nil
        }
    }
}

enum GluonEnvironment: String, EnvironmentVariable {
    case configFilePath = "GLUON_CONFIG_PATH"

    var defaultValue: String? {
        switch self {
        case .configFilePath:
            guard #available(macOS 13.0, *) else { return nil }

            let fileName = ".gluon.yml"
            var url: URL = .currentDirectory().appending(path: fileName)

            while !Gluon.fileManager.fileExists(atPath: url.path()) {
                url = url.deletingLastPathComponent()

                guard url.path() != "/" &&
                        (try? url.canonicalPath) != "/" else {
                    return nil
                }

                url = url
                    .appending(component: "../", directoryHint: .isDirectory)
                    .appending(component: fileName, directoryHint: .notDirectory)
            }
            return url.path()
        }
    }
}
