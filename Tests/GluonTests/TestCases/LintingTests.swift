//
//  ChangelogTests.swift
//
//  Created by John Biggs on 06.10.23.
//

import Foundation
import XCTest
import SwiftGit2
import ArgumentParser
import Parsing

@testable import gluon

class LintingTests: GluonTestCase {
    func invoke(_ args: [String] = []) throws {
        let lint = try Lint.parse(args)
        try lint.run()
    }

    func testNormalLinting() throws {
        // Just HEAD
        try invoke()

        // Everything down to the root
        do {
            try invoke([
                "--repo", repoPath,
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
            guard let expected = error as? CommitLintingError,
                  case .subjectDoesNotMatchRegex = expected else {
                XCTFail("Expected invalid commit error but instead got \(error)")
                return
            }
        }

        try setBranch(MockBranch.branchWithInvalidCategory)
        do {
            try invoke()
            XCTFail("Should not have succeeded when linting a branch with invalid category")
        } catch {
            guard let expected = error as? CommitLintingError,
                  case .subjectHasUnrecognizedCategory = expected else {
                XCTFail("Expected invalid commit error but instead got \(error)")
                return
            }
        }
    }

    func testTrailers() throws {
        Configuration.configuration = .init(
            projectPrefix: "TEST-",
            subjectMaxLineLength: nil,
            bodyMaxLineLength: nil,
            branchNameLinting: .init(
                projectIdsInBranches: .commitsMustMatch,
                projectIdTrailerName: "Project-Id",
                projectIdRegexes: Configuration.BranchNameLinting.default.projectIdRegexes
            ),
            commitCategories: Configuration.CommitCategory.defaultValues,
            trains: nil
        )

        try setBranch(.branchWithFullProjectIdInLastComponent)
        try invoke()

        try setBranch(.branchWithPartialProjectIdInLastComponent)
        try invoke()

        let mismatchedTrailerBranches: [MockBranch] = [
            .branchWithMismatchedFullProjectIdInLastComponent,
            .branchWithMismatchedPartialProjectIdInLastComponent
        ]

        for branch in mismatchedTrailerBranches {
            try setBranch(branch)
            do {
                try invoke()
                XCTFail("Branch with trailers mismatched from branch name should throw error, but got success")
            } catch {
                guard case let CommitLintingError.missingSpecificTrailer(name, value, commit) = error else {
                    XCTFail("Threw unexpected error: \(error)")
                    return
                }

                XCTAssertEqual(name, "Project-Id", "Name of expected missing trailer is incorrect")
                XCTAssertEqual(value, "TEST-5678", "Value of expected missing trailer is incorrect")
                XCTAssertEqual(commit.oid, MockCommit.withProjectId.oid)
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
