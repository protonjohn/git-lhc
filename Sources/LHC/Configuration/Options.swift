//
//  Options.swift
//  
//
//  Created by John Biggs on 28.11.23.
//

import Foundation
import DictionaryCoder
import LHCInternal

extension Configuration {
    /// These are the allowed values for ``Options/lintBranchNames``.
    public enum ProjectIDsInBranches: String, Codable, Equatable {
        case never
        case always
        case commitsMustMatch

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)

            switch string {
            case "never", "NO", "false":
                self = .never
            case "always", "YES", "true":
                self = .always
            case "commitsMustMatch":
                self = .commitsMustMatch
            default:
                self = .never
            }
        }
    }

    /// The list of options accepted by the `git lhc` command. For the list of
    ///
    /// For a list of options used in Fastlane builds, check out the <doc:Fastlane> article.
    public struct Options: Codable {
        /// The name of the current train.
        /// - Note: this value is normally passed by the command line.
        public let train: String?

        /// The name of the current release channel.
        /// - Note: this value is normally passed by the command line.
        public let channel: ReleaseChannel?

        /// An optional "human display name" for the build train.
        public let trainDisplayName: String?

        /// An optional tag prefix to use when searching for versions.
        public let tagPrefix: String?

        /// An optional list of build trains for the project.
        ///
        /// This is useful if you have more than product and would like to iterate through many of them.
        /// If you only have one build train, you can just set ``train``.
        public let trains: [String]?

        /// An optional project id prefix to use, when a bare ID is encountered and a default needs guessing.
        ///
        /// If your project ids look like `TEST-1234`, then this value would be equal to `TEST-`.
        public let projectIdPrefix: String?

        /// Optionally set the name of the git trailer to use that denotes a project ID. This is required for Jira
        /// integration, among other things.
        public let projectIdTrailerName: String?

        /// The name of the field that is used by Jira in your project to store release notes. Should start with `customfield_*`.
        public let jiraReleaseNotesField: String?

        /// Optionally set the maximum length to allow in a commit subject.
        public let subjectMaxLineLength: Int?

        /// Optionally set the maximum length to allow in a commit body. Lines are allowed to go over this limit if
        /// they don't contain any spaces.
        public let bodyMaxLineLength: Int?

        /// Optionally set the regular expressions used for matching against project IDs in git branch names and
        /// commit trailers. Required for commit linting and jira integration.
        public let projectIdRegexes: [String]?

        /// When a pull request is opened, if the branch matches one of the project ID regexes, whether or not every
        /// commit in that branch should contain a project id trailer matching that project ID.
        public let lintBranchNames: ProjectIDsInBranches?

        /// The commit categories to allow when linting commits.
        public let commitCategories: [String]?

        /// A map of categories to which component of the version number they should bump.
        ///
        /// By default, everything results in a patch bump, except categories starting with `feat`, which result in a
        /// minor bump, and breaking changes, which result in a major bump. If you would like to override any of those
        /// behaviors for a given category, you can define this map.
        ///
        /// One example value might be `{ "feat": "major" }`, if you wished every feature to result in an application
        /// with an incremented major version.
        public let categoryIncrements: [String: String]?

        /// The (optional) list of commit categories to automatically exclude from the changelog.
        public let changelogExcludedCategories: [String]?

        /// The (optional) corresponding display names for the commit categories above.
        public let commitCategoryDisplayNames: [String]?

        /// The (optional) reference name to use for storing/retrieving tag and commit attributes.
        public let attrsRef: String?

        public enum CodingKeys: String, CodingKey {
            case train = "train"
            case channel = "channel"
            case trainDisplayName = "human_train"
            case tagPrefix = "tag_prefix"
            case trains = "trains"
            case projectIdPrefix = "project_id_prefix"
            case projectIdTrailerName = "project_id_trailer"
            case jiraReleaseNotesField = "jira_release_notes_field"
            case subjectMaxLineLength = "commit_subject_maxlength"
            case bodyMaxLineLength = "commit_body_maxlength"
            case projectIdRegexes = "project_id_regexes"
            case lintBranchNames = "lint_branch_names"
            case commitCategories = "commit_categories"
            case categoryIncrements = "categories_increment"
            case changelogExcludedCategories = "changelog_exclude_categories"
            case commitCategoryDisplayNames = "human_commit_categories"
            case attrsRef = "attrs_ref"
        }
    }

}

extension Configuration.Defines {
    public var options: Configuration.Options {
        get throws {
            let decoder = DictionaryDecoder()
            return try decoder.decode(from: jsonDict)
        }
    }
}

extension Configuration.IngestedConfig {
    public func eval(train: String?, channel: ReleaseChannel?, define defines: Defines? = nil) throws -> Defines {
        var defines: Configuration.Defines = defines ?? [:]

        if let train = train ?? LHCEnvironment.trainName.value {
            defines["train"] = train
        }

        if let channel = channel ?? ReleaseChannel.environment {
            defines["channel"] = channel.rawValue
        }

        return try eval(initialValues: defines)
    }
}
