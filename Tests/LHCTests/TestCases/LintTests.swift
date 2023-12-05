//
//  LintingTests.swift
//
//  Created by John Biggs on 06.10.23.
//

import Foundation
import XCTest
import SwiftGit2
import ArgumentParser
import Parsing

@testable import LHC
@testable import LHCInternal
@testable import git_lhc

class LintingTests: LHCTestCase {
    func invoke(_ args: [String] = []) throws {
        var lint = try Lint.parse(args)
        try lint.run()
    }

    func testNormalLinting() throws {
        // Just HEAD
        try invoke()

        // Everything down to the root
        do {
            try invoke([
                "--repo", Self.repoPath,
                "--since", String(describing: MockCommit.developCommit(indexFromRoot: 0).oid)
            ])
        }
    }

    func testLintingBadSubject() throws {
        try setBranch(MockBranch.branchWithInvalidSubject)
        do {
            try invoke()
            XCTFail("Should not have succeeded when linting a branch with invalid subject")
        } catch {
            guard let expected = error as? LintingError,
                  case .subjectDoesNotMatchRegex = expected.reason else {
                XCTFail("Expected invalid commit error but instead got \(error)")
                return
            }
        }

        try setBranch(MockBranch.branchWithInvalidCategory)
        do {
            try invoke()
            XCTFail("Should not have succeeded when linting a branch with invalid category")
        } catch {
            guard let expected = error as? LintingError,
                  case .subjectHasUnrecognizedCategory = expected.reason else {
                XCTFail("Expected invalid commit error but instead got \(error)")
                return
            }
        }
    }

    func testTrailers() throws {
        Configuration.getConfig = { _ in
            try? .success(.init(parsing: """
            project_id_prefix = TEST-
            project_id_trailer = Project-Id
            project_id_regexes = ["([A-Z]{2,10}-)([0-9]{2,5})", "([0-9]{3,5})"]
            commit_categories = ["feat", "fix", "test", "build", "ci"]
            lint_branch_names = commitsMustMatch
            """))
        }

        let matchingTrailerBranches: [MockBranch] = [
            .branchWithFullProjectIdInLastComponent,
            .branchWithPartialProjectIdInLastComponent,
            .branchWithOtherProjectId,
            .branchWithMultipleProjectIds,
        ]

        for branch in matchingTrailerBranches {
            try setBranch(branch)
            try invoke()
        }

        let mismatchedTrailerBranches: [MockBranch] = [
            .branchWithMismatchedFullProjectIdInLastComponent,
            .branchWithMismatchedPartialProjectIdInLastComponent
        ]

        for branch in mismatchedTrailerBranches {
            try setBranch(branch)
            do {
                try invoke()
                XCTFail("Branch with trailers mismatched from branch name should throw error, but got success")
            } catch let lintingError as LintingError {
                guard case let .missingSpecificTrailer(name, value) = lintingError.reason else {
                    return
                }

                XCTAssertEqual(name, "Project-Id", "Name of expected missing trailer is incorrect")
                XCTAssertEqual(value, "TEST-5678", "Value of expected missing trailer is incorrect")
                XCTAssertEqual(lintingError.offendingCommit.oid, MockCommit.withProjectId.oid)
            } catch {
                XCTFail("Threw unexpected error: \(error)")
            }
        }
    }

    func testParsing() throws {
        let type = "test"
        let scope = "scope"
        let summary = "this is a commit summary"
        
        let onelineBody = "this is a one-line body"
        
        let oneParagraphBody = """
            this is a multi-paragraph body.
            notice how there is a second line here.
            """
        
        let multipleParagraphBody = """
            this is a multi-paragraph body.
            notice how there is a second line here.
            
            notice also that there is a second paragraph
            with a line break as well.
            """
        
        let multipleParagraphBodyWithFirstNoLineBreak = """
            this is a multi-paragraph body.
            
            notice also that there is a second paragraph
            with a line break as well.
            """
        
        let multipleParagraphBodyWithSecondNoLineBreak = """
            this is a multi-paragraph body.
            notice how there is a second line here.
            
            notice also that there is a second paragraph.
            """

        let failingExample1 = """
            feature(EAcapB): fix existing signup UI tests

            Jira-Id: CP-5457
            """
        
        let trailers: [ConventionalCommit.Trailer] = [
            .init(key: "Trailer", value: "Test value"),
            .init(key: "Other-trailer", value: "Another test value")
        ]

        do {
            let commit = try ConventionalCommit(message: "chore: initial commit")

            XCTAssertEqual(commit.header.type, "chore")
            XCTAssertNil(commit.header.scope)
            XCTAssertEqual(commit.header.summary, "initial commit")
            XCTAssertNil(commit.body)
            XCTAssertEqual(commit.trailers.count, 0)
        }
        
        do {
            let commit = try ConventionalCommit(message: .conventionalCommit(
                type: type,
                scope: scope,
                summary: summary,
                body: nil,
                breakingInSubject: false,
                trailers: nil
            ))
            
            XCTAssertEqual(commit.header.type, type)
            XCTAssertEqual(commit.header.scope, scope)
            XCTAssertEqual(commit.header.summary, summary)
        }
        
        do {
            let commit = try ConventionalCommit(message: .conventionalCommit(
                type: type,
                scope: scope,
                summary: summary,
                body: onelineBody,
                breakingInSubject: false,
                trailers: nil
            ))
            
            XCTAssertEqual(commit.header.type, type)
            XCTAssertEqual(commit.header.scope, scope)
            XCTAssertEqual(commit.header.summary, summary)
            XCTAssertEqual(commit.body, onelineBody)
        }
        
        do {
            let commit = try ConventionalCommit(message: .conventionalCommit(
                type: type,
                scope: scope,
                summary: summary,
                body: oneParagraphBody,
                breakingInSubject: false,
                trailers: nil
            ))
            
            XCTAssertEqual(commit.header.type, type)
            XCTAssertEqual(commit.header.scope, scope)
            XCTAssertEqual(commit.header.summary, summary)
            XCTAssertEqual(commit.body, oneParagraphBody)
        }
        
        do {
            let commit = try ConventionalCommit(message: .conventionalCommit(
                type: type,
                scope: scope,
                summary: summary,
                body: multipleParagraphBody,
                breakingInSubject: false,
                trailers: nil
            ))
            
            XCTAssertEqual(commit.header.type, type)
            XCTAssertEqual(commit.header.scope, scope)
            XCTAssertEqual(commit.header.summary, summary)
            XCTAssertEqual(commit.body, multipleParagraphBody)
        }
        
        do {
            let commit = try ConventionalCommit(message: .conventionalCommit(
                type: type,
                scope: scope,
                summary: summary,
                body: multipleParagraphBody,
                breakingInSubject: false,
                trailers: [trailers.first!]
            ))
            
            guard let trailer = trailers.first else {
                preconditionFailure("No trailer available in test data")
            }
            
            XCTAssertEqual(commit.header.type, type)
            XCTAssertEqual(commit.header.scope, scope)
            XCTAssertEqual(commit.header.summary, summary)
            XCTAssertEqual(commit.body, multipleParagraphBody)
            XCTAssertEqual(commit.trailers.count, 1)
            XCTAssertEqual(commit.trailers.first, .init(key: trailer.key, value: trailer.value))
        }

        do {
            let commit = try ConventionalCommit(message: .conventionalCommit(
                type: type,
                scope: scope,
                summary: summary,
                body: nil,
                breakingInSubject: false,
                trailers: [trailers.first!]
            ))

            guard let trailer = trailers.first else {
                preconditionFailure("No trailer available in test data")
            }

            XCTAssertEqual(commit.header.type, type)
            XCTAssertEqual(commit.header.scope, scope)
            XCTAssertEqual(commit.header.summary, summary)
            XCTAssertNil(commit.body)
            XCTAssertEqual(commit.trailers.count, 1)
            XCTAssertEqual(commit.trailers.first, .init(key: trailer.key, value: trailer.value))
        }

        do {
            let commit = try ConventionalCommit(message: .conventionalCommit(
                type: type,
                scope: scope,
                summary: summary,
                body: multipleParagraphBodyWithSecondNoLineBreak,
                breakingInSubject: false,
                trailers: [trailers.first!]
            ))

            guard let trailer = trailers.first else {
                preconditionFailure("No trailer available in test data")
            }

            XCTAssertEqual(commit.header.type, type)
            XCTAssertEqual(commit.header.scope, scope)
            XCTAssertEqual(commit.header.summary, summary)
            XCTAssertEqual(commit.body, multipleParagraphBodyWithSecondNoLineBreak)
            XCTAssertEqual(commit.trailers.count, 1)
            XCTAssertEqual(commit.trailers.first, .init(key: trailer.key, value: trailer.value))
        }

        do {
            let commit = try ConventionalCommit(message: .conventionalCommit(
                type: type,
                scope: scope,
                summary: summary,
                body: nil,
                breakingInSubject: false,
                trailers: trailers
            ))

            XCTAssertEqual(commit.header.type, type)
            XCTAssertEqual(commit.header.scope, scope)
            XCTAssertEqual(commit.header.summary, summary)
            XCTAssertNil(commit.body)
            XCTAssertEqual(commit.trailers.count, 2)
            XCTAssertEqual(
                commit.trailers.first,
                .init(key: "Trailer", value: "Test value")
            )
            XCTAssertEqual(
                commit.trailers.second,
                .init(key: "Other-trailer", value: "Another test value")
            )
        }

        do {
            let commit = try ConventionalCommit(message: .conventionalCommit(
                type: type,
                scope: scope,
                summary: summary,
                body: multipleParagraphBodyWithFirstNoLineBreak,
                breakingInSubject: false,
                trailers: trailers
            ))

            XCTAssertEqual(commit.header.type, type)
            XCTAssertEqual(commit.header.scope, scope)
            XCTAssertEqual(commit.header.summary, summary)
            XCTAssertEqual(commit.body, multipleParagraphBodyWithFirstNoLineBreak)
            XCTAssertEqual(commit.trailers.count, 2)
            XCTAssertEqual(
                commit.trailers.first,
                .init(key: "Trailer", value: "Test value")
            )
            XCTAssertEqual(
                commit.trailers.second,
                .init(key: "Other-trailer", value: "Another test value")
            )
        }

        do {
            let commit = try ConventionalCommit(message: failingExample1)

            XCTAssertEqual(commit.header.type, "feature")
            XCTAssertEqual(commit.header.scope, "EAcapB")
            XCTAssertEqual(commit.header.summary, "fix existing signup UI tests")
            XCTAssertNil(commit.body)
            XCTAssertEqual(commit.trailers.count, 1)
            XCTAssertEqual(
                commit.trailers.first,
                .init(key: "Jira-Id", value: "CP-5457")
            )
        }
    }
}

extension String {
    static func conventionalCommit(
        type: String,
        scope: String?,
        summary: String,
        body: String?,
        breakingInSubject: Bool,
        trailers: [ConventionalCommit.Trailer]?
    ) -> Self {
        ConventionalCommit(
            header: .init(
                type: type,
                scope: scope,
                isBreaking: breakingInSubject,
                summary: summary
            ),
            body: body,
            trailers: trailers ?? []
        ).description
    }
}
