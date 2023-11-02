//
//  Lint.swift
//  
//
//  Created by John Biggs on 06.10.23.
//

import Foundation
import ArgumentParser
import SwiftGit2

struct Lint: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Lint a range of commits according to the conventional commit format."
    )

    @OptionGroup()
    var parent: Gluon.Options

    @Option(help: "Where to start linting. Defaults to the parent commit of HEAD, if no CI environment is detected.")
    var since: String?

    static var config: Configuration {
        .configuration
    }

    func run() throws {
        SwiftGit2.initialize()
        let repo = try Gluon.openRepo(at: parent.repo)
        let head = try repo.currentBranch() ?? repo.HEAD()

        var startOID: ObjectID?
        if let since {
            startOID = try repo.oid(for: since)
        } else if GitlabEnvironment.isCI {
            let ciStartOID: ObjectID?
            do {
                ciStartOID = try lintBaseFromGitlabCI(for: repo, head: head)
            } catch {
                Gluon.print("Could not invoke lint job from CI: \(error)", error: true)
                return
            }

            guard let ciStartOID else {
                Gluon.print("Could not determine commit base object for linting. Aborting.", error: true)
                return
            }
            startOID = ciStartOID
        }
        if startOID == nil {
            startOID = try repo.commit(head.oid).parentOIDs.first
        }
        
        let (branch, commits) = try repo.commits(since: startOID)

        var errors: [LintingError] = []
        for commit in commits {
            do {
                try lint(commit: commit, branch: branch)
            } catch let lintingError as LintingError {
                errors.append(lintingError)
            }
        }

        guard errors.isEmpty else {
            if errors.count == 1, let first = errors.first {
                throw first
            } else {
                throw MultipleLintingErrors(errors: errors)
            }
        }

        Gluon.print("Commit linting passed. No issues found.")
    }

    func lintBaseFromGitlabCI(for repo: Repositoryish, head: ReferenceType) throws -> ObjectID? {
        var refName: String?
        let envVars: [GitlabEnvironment] = [.commitBeforeChange, .mergeRequestDiffBaseSha, .defaultBranch]
        for envVar in envVars {
            if let value = envVar.value, !value.isEmpty, value != .nullSha {
                refName = value
                break
            }
        }

        guard let refName else { return nil }

        guard let oid = try repo.oid(for: refName) else { return nil }
        guard oid != head.oid, try repo.isReachable(oid, from: head.oid) else { return nil }

        return oid
    }

    func lint(commit: Commitish, branch: Branchish?) throws {
        let components = commit.message
            .split(separator: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard let subject = components.first else {
            throw LintingError(commit, .missingSubject)
        }

        try lint(subject: subject, of: commit)

        if components.count > 1 {
            try lint(paragraphs: components[1...], of: commit)
        }

        try lintTrailers(of: commit, on: branch)
    }

    func lint(subject: String, of commit: Commitish) throws {
        if let subjectMaxLength = Self.config.subjectMaxLineLength,
           subject.count > subjectMaxLength {
            throw LintingError(commit, .subjectTooLong(configuredMax: subjectMaxLength))
        }

        let regex = "^([a-z]+)(\\([a-zA-Z0-9\\-\\_]+\\)){0,1}(!){0,1}: .*"
        guard let match = try? Regex(regex).wholeMatch(in: subject) else {
            throw LintingError(commit, .subjectDoesNotMatchRegex(regex: regex))
        }
        guard let categorySubstring = match.output[1].substring else {
            throw LintingError(commit, .subjectHasMissingCategory)
        }

        let category = String(categorySubstring)
        let categories = Configuration.get(\.commitCategories)
        guard categories.contains(where: { $0.name == category }) != false else {
            throw LintingError(commit, .subjectHasUnrecognizedCategory(category: category))
        }
    }

    func lint(paragraphs: ArraySlice<String>, of commit: Commitish) throws {
        if let bodyMaxColumns = Self.config.bodyMaxLineLength,
           paragraphs.contains(where: { paragraph in
           paragraph.split(separator: "\n")
               .contains(where: { line in line.count > bodyMaxColumns })
        }) {
            throw LintingError(commit, .lineInBodyTooLong(configuredMax: bodyMaxColumns))
        }
    }

    func lintTrailers(of commit: Commitish, on branch: Branchish?) throws {
        guard let trailerName = Self.config.projectIdTrailerName,
              let projectIds = branch?.projectIds, !projectIds.isEmpty else {
            return
        }

        let trailers: [Trailerish]
        do {
            trailers = try commit.trailers
        } catch {
            throw LintingError(commit, .trailersMissing(underlyingError: error))
        }

        for var projectId in projectIds {
            if let prefix = Self.config.projectPrefix, !projectId.starts(with: prefix) {
                projectId = prefix + projectId
            }

            guard trailers.contains(where: {
                $0.key == trailerName &&
                $0.value == projectId
            }) else {
                throw LintingError(commit, .missingSpecificTrailer(named: trailerName, withValue: projectId))
            }
        }
    }
}

struct MultipleLintingErrors: Error, CustomStringConvertible {
    let errors: [LintingError]

    var description: String {
        """
        \(errors.count) commits have errors:
        \(errors.map(\.description).joined(separator: "\n\n"))
        """
    }
}

struct LintingError: Error, CustomStringConvertible {
    enum Reason {
        case missingSubject
        case subjectTooLong(configuredMax: Int)
        case subjectDoesNotMatchRegex(regex: String)
        case subjectHasMissingCategory
        case subjectHasUnrecognizedCategory(category: String)
        case lineInBodyTooLong(configuredMax: Int)
        case trailersMissing(underlyingError: Error)
        case missingSpecificTrailer(named: String, withValue: String?)
    }

    let offendingCommit: Commitish
    let reason: Reason

    var description: String {
        var result: String

        switch reason {
        case .missingSubject:
            result = "Commit is missing subject"
        case let .subjectTooLong(configuredMax):
            result = "Commit has a subject line that is longer than \(configuredMax) characters"
        case .subjectDoesNotMatchRegex:
            result = "Commit subject does not meet conventional commit specifications"
        case let .subjectHasUnrecognizedCategory(category):
            result = "Commit subject has unrecognized category '\(category)'"
        case .subjectHasMissingCategory:
            result = "Commit subject has missing category"
        case let .lineInBodyTooLong(configuredMax):
            result = "Commit body has one or more lines longer than \(configuredMax) characters"
        case let .trailersMissing(underlyingError):
            result = "Commit is missing one or more trailers (\(underlyingError))"
        case let .missingSpecificTrailer(name, expectedValue):
            result = "Commit is missing a '\(name)' trailer"
            if let expectedValue {
                result += " with expected value '\(expectedValue)'"
            }
        }

        result += ":\n\(offendingCommit.description)"
        return result
    }
}

extension LintingError {
    init(_ commit: Commitish, _ reason: Reason) {
        self.init(offendingCommit: commit, reason: reason)
    }
}

extension Branchish {
    var projectIds: [String] {
        var result: [String] = []
        let components = name.split(separator: "/")

        guard let regexStrings = Configuration.configuration.branchNameLinting?.projectIdRegexes else {
            return []
        }

        do {
            for regexString in regexStrings {
                let regex = try Regex(regexString)
                for component in components {
                    var string: Substring = component[...]
                    while let match = try regex.firstMatch(in: string),
                          let substring = match.output[0].substring {
                        result.append(String(substring))
                        string = string.advanced(by: substring.count)
                    }
                    guard result.isEmpty else { return result }
                }
            }
        } catch {
            assertionFailure("Regex compilation error in \(#file) on line \(#line): \(error)")
        }

        return []
    }
}

extension String {
    static let nullSha = "0000000000000000000000000000000000000000"
}
