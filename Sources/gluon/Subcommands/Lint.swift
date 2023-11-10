//
//  Lint.swift
//  
//
//  Created by John Biggs on 06.10.23.
//

import Foundation
import ArgumentParser
import SwiftGit2

struct Lint: ParsableCommand, VerboseCommand {
    static let configuration = CommandConfiguration(
        abstract: "Lint a range of commits according to the conventional commit format."
    )

    @OptionGroup()
    var parent: Gluon.Options

    @Option(help: "Where to start linting. Defaults to the parent commit of HEAD, if no CI environment is detected.")
    var since: String?

    @Flag(
        name: .shortAndLong,
        help: "Without the verbose option, no output is produced upon success."
    )
    var verbose: Bool = false

    static var config: Configuration {
        .configuration
    }

    struct ProjectID {
        let value: String
        let components: [String]
    }

    func run() throws {
        SwiftGit2.initialize()
        let repo = try Gluon.openRepo(at: parent.repo)
        let head = try repo.currentBranch() ?? repo.HEAD()
        if let branch = head as? Branchish {
            printIfVerbose("Linting branch \(branch.name).")
        }

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

            printIfVerbose("Linting from commit: \(ciStartOID.description)")

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
        printIfVerbose("Linting commit \(commit.oid)...")

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

        let branchName = branch?.name ?? Gluon.branchName
        try lintTrailers(of: commit, branchName: branchName)

        printIfVerbose("No issues found.\n")
    }

    func lint(subject: String, of commit: Commitish) throws {
        printIfVerbose("Checking commit summary...")
        if let subjectMaxLength = Self.config.subjectMaxLineLength,
           subject.count > subjectMaxLength {
            throw LintingError(commit, .subjectTooLong(configuredMax: subjectMaxLength))
        }

        let regex = "^([a-z0-9]+)(\\([a-zA-Z0-9\\-\\_]+\\)){0,1}(!){0,1}: .*"
        guard let match = try? Regex(regex).wholeMatch(in: subject) else {
            throw LintingError(commit, .subjectDoesNotMatchRegex(regex: regex))
        }
        guard let categorySubstring = match.output[1].substring else {
            throw LintingError(commit, .subjectHasMissingCategory)
        }

        let category = String(categorySubstring)
        guard let categories = Configuration.configuration.commitCategories else {
            return
        }

        printIfVerbose("Checking that commit type matches configured categories...")
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
            printIfVerbose("Checking line lengths...")
            throw LintingError(commit, .lineInBodyTooLong(configuredMax: bodyMaxColumns))
        }
    }

    func lintTrailers(of commit: Commitish, branchName: String?) throws {
        guard let trailerName = Self.config.projectIdTrailerName,
              let branchName else {
            printIfVerbose("No trailer name configured or not a branch, skipping trailer linting.")

            return
        }

        let projectIds = branchName.components(separatedBy: "/")
            .compactMap(ProjectID.init(string:))

        printIfVerbose("Linting trailers...")

        let trailers: [Trailerish]
        do {
            trailers = try commit.trailers
        } catch {
            throw LintingError(commit, .trailersMissing(underlyingError: error))
        }

        for projectId in projectIds {
            printIfVerbose("Checking that commit has trailer for \(projectId.value)...")

            guard trailers.contains(where: {
                $0.key == trailerName &&
                $0.value == projectId.value
            }) else {
                throw LintingError(commit, .missingSpecificTrailer(named: trailerName, withValue: projectId.value))
            }
        }
    }
}

extension Lint.ProjectID {
    init?(string: String) {
        guard let regexes = Configuration.BranchNameLinting.branchRegexes, !regexes.isEmpty else {
            return nil
        }

        for regex in regexes {
            guard let match = try? regex.firstMatch(in: string),
                  let firstGroup = match.output.first,
                  let substring = firstGroup.substring else {
                continue
            }

            let matchString = String(substring)
            if match.output.count > 1,
               let secondGroupSubstring = match.output[1].substring,
               matchString != String(secondGroupSubstring) {
                self.value = matchString
                self.components = match.output[1...].compactMap { value in
                    guard let component = value.substring, !component.isEmpty else {
                        return nil
                    }
                    return String(component)
                }
            } else if let prefix = Configuration.configuration.projectPrefix,
                      !matchString.starts(with: prefix) {
                self.value = prefix + matchString
                self.components = [prefix, matchString]
            } else {
                self.value = matchString
                self.components = []
            }
            return
        }

        return nil
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

extension String {
    static let nullSha = "0000000000000000000000000000000000000000"
}
