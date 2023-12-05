//
//  CreateReleaseTests.swift
//  
//
//  Created by John Biggs on 26.10.23.
//

import Foundation
import XCTest

@testable import LHC
@testable import LHCInternal
@testable import git_lhc

class CreateReleaseTests: LHCTestCase {
    func invoke(_ args: [String] = []) async throws -> CreateRelease {
        var createRelease = try CreateRelease.parse(args)
        try await createRelease.run()
        return createRelease
    }

    func subtestCreatingNewProdRelease(train: String?) async throws {
        var args = ["--push"]
        if let train {
            args.append(contentsOf: ["--train", train])
        }

        var invocation = try await invoke(args)
        let options = try invocation.parent.options?.get()

        XCTAssertEqual(repoUnderTest.pushes.count, 1)
        guard let first = repoUnderTest.pushes.first,
              case let .sshPath(publicKeyPath, privateKeyPath, passphrase) = first.0 else {
            XCTFail("Push object was missing or has incorrect credentials")
            return
        }

        XCTAssertEqual(privateKeyPath, "/Users/test/.ssh/id_rsa")
        XCTAssertEqual(publicKeyPath, "/Users/test/.ssh/id_rsa.pub")
        XCTAssertEqual(passphrase, "foo bar")

        guard let reference = first.1 as? MockTagReference,
              case let .annotated(name, tag) = reference else {
            XCTFail("Pushed tag is not a valid tag reference")
            return
        }

        guard let head = try repoUnderTest.currentBranch() else {
            XCTFail("Could not get current branch.")
            return
        }

        let expectedTagName = "refs/tags/\(options?.tagPrefix ?? "")1.0.0"
        XCTAssertEqual(name, expectedTagName)
        XCTAssertEqual(tag.oid, head.oid)
        
        if let train = options?.train {
            XCTAssertEqual(tag.message, """
            release: \(train) 1.0.0

            - Release notes content
            """)
        }
    }

    func testCreatingNewProdRelease() async throws {
        Internal.jiraClient = MockJiraClient.init(issues: [
            .init(
                id: "12345",
                summary: nil,
                fields: .init(
                    assignee: nil,
                    summary: "",
                    status: .init(
                        name: "",
                        description: nil
                    ),
                    fixVersions: nil,
                    description: "",
                    created: .now,
                    extraFields: [MockJiraClient.customField: "Release notes content"]
                )
            )
        ])

        try await subtestCreatingNewProdRelease(train: nil)

        Configuration.getConfig = { _ in
            try? .success(.init(parsing: """
            train = test
            tag_prefix = train/
            project_id_prefix = TEST-
            project_id_trailer = Project-Id
            jira_release_notes_field = \(MockJiraClient.customField)
            commit_categories = ["feat", "fix", "test", "build", "ci"]
            """))
        }

        try await subtestCreatingNewProdRelease(train: "test")
    }

    func subtestCreatingPreleaseForVersion(train: String? = nil, channel: ReleaseChannel, prereleaseBuild: String = "1") async throws -> CreateRelease {
        var args = ["--push", "--channel", channel.rawValue]
        if let train {
            args.append(contentsOf: ["--train", train])
        }
        var invocation = try await invoke(args)
        let options = try invocation.parent.options?.get()

        XCTAssertEqual(repoUnderTest.pushes.count, 1)
        guard let first = repoUnderTest.pushes.first,
              case let .sshPath(publicKeyPath, privateKeyPath, passphrase) = first.0 else {
            XCTFail("Push object was missing or has incorrect credentials")
            return invocation
        }

        XCTAssertEqual(privateKeyPath, "/Users/test/.ssh/id_rsa")
        XCTAssertEqual(publicKeyPath, "/Users/test/.ssh/id_rsa.pub")
        XCTAssertEqual(passphrase, "foo bar")

        guard let reference = first.1 as? MockTagReference,
              case let .annotated(name, tag) = reference else {
            XCTFail("Pushed tag is not a valid tag reference")
            return invocation
        }

        guard let head = try repoUnderTest.currentBranch() else {
            XCTFail("Could not get current branch.")
            return invocation
        }
        let expectedTagName = "refs/tags/\(options?.tagPrefix ?? "")1.0.0-\(channel.rawValue).\(prereleaseBuild)"
        XCTAssertEqual(name, expectedTagName)
        XCTAssertEqual(tag.oid, head.oid)

        return invocation
    }

    func commitAndSetHEAD(repo: inout MockRepository) throws -> MockCommit {
        let head = try repo.HEAD()
        let commit = try repo.commit(head.oid)
        let nextCommit = try repo.commit(
            tree: .random(),
            parents: [commit],
            message: "fix(fix): fixy fix",
            signature: .cookie
        )
        var branch = try repo.currentBranch() as! MockBranch
        branch.oid = nextCommit.oid
        repo.localBranches[branch] = try repo.commits(from: nextCommit.oid, since: nil).map { $0 as! MockCommit }
        repo.head = branch
        return commit as! MockCommit
    }

    func commitAndTag(repo: inout MockRepository, tagName: String) throws -> (MockCommit, MockTagReference) {
        let nextCommit = try commitAndSetHEAD(repo: &repo)
        let tag: MockTagReference = .lightweight(name: tagName, tagging: nextCommit)
        repo.tags.append(tag)
        return (nextCommit, tag)
    }

    func testCreatingPrereleasesForVersion() async throws {
        for channel in ReleaseChannel.prereleaseChannels {
            _ = try await subtestCreatingPreleaseForVersion(channel: channel)

            let oldRepo = MockRepository.mock
            var repo = oldRepo
            _ = try commitAndTag(repo: &repo, tagName: "1.0.0-\(channel.rawValue).1")

            MockRepository.mock = repo
            _ = try await subtestCreatingPreleaseForVersion(channel: channel, prereleaseBuild: "2")
            MockRepository.mock = oldRepo
        }

        let train = "test"
        Configuration.getConfig = { _ in
            try? .success(.init(parsing: """
            train = \(train)
            tag_prefix = train/
            commit_categories = ["feat", "fix", "test", "build", "ci"]
            """))
        }

        for channel in ReleaseChannel.prereleaseChannels {
            var invocation = try await subtestCreatingPreleaseForVersion(train: train, channel: channel)
            let options = try invocation.parent.options?.get()

            let oldRepo = MockRepository.mock
            var repo = oldRepo
            _ = try commitAndTag(repo: &repo, tagName: "\(options?.tagPrefix ?? "")1.0.0-\(channel.rawValue).1")

            MockRepository.mock = repo
            _ = try await subtestCreatingPreleaseForVersion(train: train, channel: channel, prereleaseBuild: "2")
            MockRepository.mock = oldRepo
        }
    }
}
