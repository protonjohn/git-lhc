//
//  CreateReleaseTests.swift
//  
//
//  Created by John Biggs on 26.10.23.
//

import Foundation
import XCTest
@testable import gluon

class CreateReleaseTests: GluonTestCase {
    func invoke(_ args: [String] = []) throws {
        var createRelease = try CreateRelease.parse(args)
        try createRelease.run()
    }

    func subtestCreatingNewProdRelease(train: Configuration.Train? = nil) throws {
        var args = ["--push"]
        if let train {
            args.append(contentsOf: ["--train", train.name])
        }
        try invoke(args)

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
        let expectedTagName = "refs/tags/\(train?.tagPrefix ?? "")1.0.0"
        XCTAssertEqual(name, expectedTagName)
        XCTAssertEqual(tag.oid, head.oid)
    }

    func testCreatingNewProdRelease() throws {
        try subtestCreatingNewProdRelease()

        let train: Configuration.Train = .init(name: "test", tagPrefix: "train/")
        Configuration.configuration = .init(
            projectPrefix: nil,
            projectIdTrailerName: nil,
            subjectMaxLineLength: nil,
            bodyMaxLineLength: nil,
            branchNameLinting: nil,
            commitCategories: Configuration.default.commitCategories,
            trains: [train]
        )

        try subtestCreatingNewProdRelease()
    }

    func subtestCreatingPreleaseForVersion(train: Configuration.Train? = nil, channel: ReleaseChannel, prereleaseBuild: String = "1") throws {
        var args = ["--push", "--channel", channel.rawValue]
        if let train {
            args.append(contentsOf: ["--train", train.name])
        }
        try invoke(args)

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
        let expectedTagName = "refs/tags/\(train?.tagPrefix ?? "")1.0.0-\(channel.rawValue).\(prereleaseBuild)"
        XCTAssertEqual(name, expectedTagName)
        XCTAssertEqual(tag.oid, head.oid)
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

    func testCreatingPrereleasesForVersion() throws {
        for channel in ReleaseChannel.prereleaseChannels {
            try subtestCreatingPreleaseForVersion(channel: channel)

            let oldRepo = MockRepository.mock
            var repo = oldRepo
            _ = try commitAndTag(repo: &repo, tagName: "1.0.0-\(channel.rawValue).1")

            MockRepository.mock = repo
            try subtestCreatingPreleaseForVersion(channel: channel, prereleaseBuild: "2")
            MockRepository.mock = oldRepo
        }

        let train: Configuration.Train = .init(name: "test", tagPrefix: "train/")
        Configuration.configuration = .init(
            projectPrefix: nil,
            projectIdTrailerName: nil,
            subjectMaxLineLength: nil,
            bodyMaxLineLength: nil,
            branchNameLinting: nil,
            commitCategories: Configuration.default.commitCategories,
            trains: [train]
        )

        for channel in ReleaseChannel.prereleaseChannels {
            try subtestCreatingPreleaseForVersion(train: train, channel: channel)

            let oldRepo = MockRepository.mock
            var repo = oldRepo
            _ = try commitAndTag(repo: &repo, tagName: "\(train.tagPrefix ?? "")1.0.0-\(channel.rawValue).1")

            MockRepository.mock = repo
            try subtestCreatingPreleaseForVersion(train: train, channel: channel, prereleaseBuild: "2")
            MockRepository.mock = oldRepo
        }
    }
}
