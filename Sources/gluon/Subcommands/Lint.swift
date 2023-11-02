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

    @Option(help: "Where to start linting. Defaults to the parent commit of HEAD, if no CI env variables are set.")
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
                Gluon.print("Could not invoke lint job from CI: \(error)", to: &FileHandle.stderr)
                return
            }

            guard let ciStartOID else { return }
            startOID = ciStartOID
        }
        if startOID == nil {
            startOID = try repo.commit(head.oid).parentOIDs.first
        }
        
        let (branch, commits) = try repo.commits(since: startOID)

        for commit in commits {
            try lint(commit: commit, branch: branch)
        }
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
            throw CommitLintingError.missingSubject(commit)
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
            throw CommitLintingError.subjectTooLong(subject: subject, of: commit, configuredMax: subjectMaxLength)
        }

        let regex = "^([a-z]+)(\\([a-zA-Z0-9\\-\\_]+\\)){0,1}(!){0,1}: .*"
        guard let match = try? Regex(regex).wholeMatch(in: subject) else {
            throw CommitLintingError.subjectDoesNotMatchRegex(subject: subject, of: commit, regex: regex)
        }
        guard let categorySubstring = match.output[1].substring else {
            throw CommitLintingError.subjectHasMissingCategory(subject: subject, of: commit)
        }

        let category = String(categorySubstring)
        let categories = Configuration.get(\.commitCategories)
        guard categories.contains(where: { $0.name == category }) != false else {
            throw CommitLintingError.subjectHasUnrecognizedCategory(subject: subject, category: category, of: commit)
        }
    }

    func lint(paragraphs: ArraySlice<String>, of commit: Commitish) throws {
        if let bodyMaxColumns = Self.config.bodyMaxLineLength,
           paragraphs.contains(where: { paragraph in
           paragraph.split(separator: "\n")
               .contains(where: { line in line.count > bodyMaxColumns })
        }) {
            throw CommitLintingError.lineInBodyTooLong(of: commit, configuredMax: bodyMaxColumns)
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
            throw CommitLintingError.trailersMissing(from: commit, underlyingError: error)
        }

        for var projectId in projectIds {
            if let prefix = Self.config.projectPrefix, !projectId.starts(with: prefix) {
                projectId = prefix + projectId
            }

            guard trailers.contains(where: {
                $0.key == trailerName &&
                $0.value == projectId
            }) else {
                throw CommitLintingError.missingSpecificTrailer(named: trailerName, withValue: projectId, from: commit)
            }
        }
    }
}

enum CommitLintingError: Error, CustomStringConvertible {
    case missingSubject(Commitish)
    case subjectTooLong(subject: String, of: Commitish, configuredMax: Int)
    case subjectDoesNotMatchRegex(subject: String, of: Commitish, regex: String)
    case subjectHasMissingCategory(subject: String, of: Commitish)
    case subjectHasUnrecognizedCategory(subject: String, category: String, of: Commitish)
    case lineInBodyTooLong(of: Commitish, configuredMax: Int)
    case trailersMissing(from: Commitish, underlyingError: Error)
    case missingSpecificTrailer(named: String, withValue: String?, from: Commitish)

    var description: String {
        let offendingCommit: Commitish?
        var result: String

        switch self {
        case let .missingSubject(commit):
            result = "Commit is missing subject"
            offendingCommit = commit
        case let .subjectTooLong(_, commit, configuredMax):
            result = "Commit has a subject line that is longer than \(configuredMax) characters"
            offendingCommit = commit
        case let .subjectDoesNotMatchRegex(_, commit, _):
            result = "Commit subject does not meet conventional commit specifications"
            offendingCommit = commit
        case let .subjectHasUnrecognizedCategory(_, category, commit):
            result = "Commit subject has unrecognized category '\(category)'"
            offendingCommit = commit
        case let .subjectHasMissingCategory(_, commit):
            result = "Commit subject has missing category"
            offendingCommit = commit
        case let .lineInBodyTooLong(commit, configuredMax):
            result = "Commit body has one or more lines longer than \(configuredMax) characters"
            offendingCommit = commit
        case let .trailersMissing(commit, underlyingError):
            result = "Commit is missing one or more trailers (\(underlyingError))"
            offendingCommit = commit
        case let .missingSpecificTrailer(name, expectedValue, commit):
            result = "Commit is missing a '\(name)' trailer"
            if let expectedValue {
                result += " with expected value '\(expectedValue)'"
            }
            offendingCommit = commit
        }

        if let offendingCommit {
            result += ":\n\(offendingCommit.message)"
        }

        return result
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
