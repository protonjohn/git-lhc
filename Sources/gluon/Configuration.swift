//
//  Configuration.swift
//  
//
//  Created by John Biggs on 07.10.23.
//

import Foundation
import Yams

struct Configuration: Codable, Equatable {
    enum ProjectIDsInBranches: String, Codable, Equatable {
        case never
        case always
        case commitsMustMatch
    }

    struct BranchNameLinting: Codable, Equatable {
        let projectIdsInBranches: ProjectIDsInBranches?
        let projectIdRegexes: [String]

        static let branchRegexes: [Regex<AnyRegexOutput>]? = {
            Configuration.configuration.branchNameLinting?.projectIdRegexes.compactMap {
                do {
                    return try Regex($0)
                } catch {
                    Gluon.print("Warning: regex \($0) is invalid: \(error)", error: true)
                    return nil
                }
            }
        }()

        static let `default`: Self = .init(
            projectIdsInBranches: .never,
            projectIdRegexes: [
                "([A-Z]{2,10}-)([0-9]{2,5})",
                "([0-9]{3,5})",
            ]
        )
    }

    struct CommitCategory: Codable, Equatable {
        let name: String
        let description: String
        let changelogName: String?
        let excludeFromChangelog: Bool?
        let increment: ConventionalCommit.VersionBump?

        init(
            name: String,
            description: String,
            changelogName: String? = nil,
            excludeFromChangelog: Bool = false,
            increment: ConventionalCommit.VersionBump? = nil
        ) {
            self.name = name
            self.description = description
            self.changelogName = changelogName
            self.excludeFromChangelog = excludeFromChangelog
            self.increment = increment
        }

        static let defaultValues: [Self] = [
            .init(name: "feat", description: "Implements a new feature.", increment: .minor),
            .init(name: "fix", description: "Fixes an issue."),
            .init(name: "test", description: "Fixes or implements a test."),
            .init(name: "refactor", description: "Changes code, but does not implement a fix or feature."),
            .init(name: "build", description: "Changes the build system or external dependencies."),
            .init(name: "doc", description: "Corrects/updates documentation for a feature or architectural decision."),
            .init(name: "ci", description: "Fixes or implements a continuous integration feature."),
        ]
    }

    enum VersionReplacementFormat: String, Codable {
        case json
        case yaml
        case plist
        case plaintext

        var isStructured: Bool {
            self != .plaintext
        }
    }

    enum VersionReplacementItem: String, Codable {
        case version
        case fullVersion
        case identifiers
        case prereleaseIdentifiers
        case buildIdentifiers
    }

    struct VersionReplacement: Codable, Equatable {
        let key: String
        let file: String
        let item: VersionReplacementItem?
        let format: VersionReplacementFormat?
    }
    
    struct Train: Codable, Equatable {
        let name: String
        let displayName: String?
        let tagPrefix: String?
        let replace: [VersionReplacement]?
    }

    let projectPrefix: String?
    let projectIdTrailerName: String?
    let jiraReleaseNotesField: String?

    let subjectMaxLineLength: Int?
    let bodyMaxLineLength: Int?

    let branchNameLinting: BranchNameLinting?
    let commitCategories: [CommitCategory]?
    let trains: [Train]?

    static let `default`: Self = .init(
        projectPrefix: nil,
        projectIdTrailerName: nil,
        jiraReleaseNotesField: nil,
        subjectMaxLineLength: nil,
        bodyMaxLineLength: 72,
        branchNameLinting: .default,
        commitCategories: CommitCategory.defaultValues,
        trains: nil
    )

    static var configuration: Self = {
        do {
            return try parsed()
        } catch {
            Gluon.print("""
                Warning: could not decode configuration file at \
                \(String(describing: Gluon.configFilePath)): \(error)
                """,
                error: true
            )
            return .default
        }
    }()

    static func get<V>(_ keyPath: KeyPath<Self, Optional<V>>) -> V {
        if let configValue = Configuration.configuration[keyPath: keyPath].optional {
            return configValue
        }

        guard let defaultValue = Configuration.default[keyPath: keyPath].optional else {
            preconditionFailure("No default prerelease identifiers defined")
        }

        return defaultValue
    }

    static func parsed() throws -> Self {
        guard let configFilePath = Gluon.configFilePath,
              let contents = Gluon.fileManager.contents(atPath: configFilePath) else {
            return .default
        }

        let decoder = YAMLDecoder(encoding: .utf8)
        return try decoder.decode(Self.self, from: contents)
    }

    static func train(named name: String) throws -> Train {
        let config = Self.configuration
        guard let configTrain = config.trains?.first(where: { $0.name == name || $0.displayName == name }) else {
            throw ConfigurationError.noSuchTrain(name)
        }
        return configTrain
    }
}

extension Configuration {
    static let example: Self? = {
        guard let path = Bundle.module.path(forResource: "gluon.example", ofType: "yml") else {
            return nil
        }
        guard let contents = FileManager.default.contents(atPath: path) else {
            return nil
        }
        return try? YAMLDecoder().decode(Configuration.self, from: contents)
    }()
}

enum ConfigurationError: Error, CustomStringConvertible {
    case noSuchTrain(String)
    case invalidRegex(String, underlyingError: Error)

    var description: String {
        switch self {
        case let .noSuchTrain(name):
            return "No train exists with name \(name)."
        case let .invalidRegex(string, underlyingError):
            return """
                Configuration contains an invalid regular expression: \(string).
                Parse error: \(underlyingError)
                """
        }
    }
}
