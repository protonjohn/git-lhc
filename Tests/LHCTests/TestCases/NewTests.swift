//
//  NewTests.swift
//  
//
//  Created by John Biggs on 26.10.23.
//

import Foundation
import XCTest

@testable import LHC
@testable import LHCInternal
@testable import git_lhc

class NewTests: LHCTestCase {
    func invoke(_ args: [String] = []) throws -> New {
        var new = try New.parse(args)
        try new.run()
        return new
    }

    func subtestCreatingNewProdRelease(train: String?) throws {
        var args = ["--push"]
        if let train {
            args.append(contentsOf: ["--train", train])
        }

        Internal.loadTrains = { _ in
            [
                Trains.TrainImpl(
                    tagPrefix: nil,
                    releaseChannel: .production,
                    linter: Trains.LinterSettingsImpl(
                        testProjectIdPrefix: "TEST-",
                        requireCommitTypes: [
                                "feat",
                                "fix",
                                "test",
                                "build",
                                "ci",
                        ]
                    ),
                    trailers: Trains.TrailersImpl(
                        testProjectId: "Project-Id"
                    )
                )
            ]
        }

        var invocation = try invoke(args)
        let train = try invocation.parent.train?.get()

        XCTAssertEqual(repoUnderTest.pushes.count, 1)
        guard let first = repoUnderTest.pushes.first else {
            XCTFail("Push object was missing or has incorrect credentials")
            return
        }

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
        XCTAssertEqual(tag.target.oid, head.oid)
        
        if let train = train?.displayName {
            XCTAssertEqual(tag.message, "release: \(train) 1.0.0")
        }
    }

    func testCreatingNewProdRelease() throws {
        try subtestCreatingNewProdRelease(train: nil)

        try subtestCreatingNewProdRelease(train: "test")
    }

    func subtestCreatingPreleaseForVersion(train: String? = nil, channel: ReleaseChannel, prereleaseBuild: String = "1") throws -> New {
        var args = ["--push", "--channel", channel.rawValue]
        if let train {
            args.append(contentsOf: ["--train", train])

            Internal.loadTrains = { _ in
                [
                    Trains.TrainImpl(
                        tagPrefix: nil,
                        releaseChannel: .init(rawValue: channel.rawValue)!,
                        linter: Trains.LinterSettingsImpl(
                            testProjectIdPrefix: "TEST-",
                            requireCommitTypes: [
                                    "feat",
                                    "fix",
                                    "test",
                                    "build",
                                    "ci",
                            ]
                        ),
                        trailers: Trains.TrailersImpl(
                            testProjectId: "Project-Id"
                        )
                    )
                ]
            }
        } else {
            Internal.loadTrains = { _ in
                [Trains.TrainImpl(tagPrefix: nil, releaseChannel: .init(rawValue: channel.rawValue)!)]
            }
        }

        var invocation = try invoke(args)
        let train = try invocation.parent.train?.get()

        XCTAssertEqual(repoUnderTest.pushes.count, 1)
        guard let first = repoUnderTest.pushes.first else {
            XCTFail("Push object was missing or has incorrect credentials")
            return invocation
        }

        guard let reference = first.1 as? MockTagReference,
              case let .annotated(name, tag) = reference else {
            XCTFail("Pushed tag is not a valid tag reference")
            return invocation
        }

        guard let head = try repoUnderTest.currentBranch() else {
            XCTFail("Could not get current branch.")
            return invocation
        }
        let expectedTagName = "refs/tags/\(train?.tagPrefix ?? "")1.0.0-\(channel.rawValue).\(prereleaseBuild)"
        XCTAssertEqual(name, expectedTagName)
        XCTAssertEqual(tag.target.oid, head.oid)

        return invocation
    }

    func commitAndSetHEAD(repo: inout MockRepository) throws -> MockCommit {
        let head = try repo.HEAD()
        let commit = try repo.commit(head.oid)
        let nextCommit = try repo.commit(
            tree: .random(),
            parents: [commit],
            message: "fix(fix): fixy fix",
            signature: .cookie,
            signingCallback: {
                "signature of \(String(data: $0, encoding: .utf8) ?? "")"
                    .data(using: .utf8)!
            }
        )
        var branch = try repo.currentBranch() as! MockBranch
        branch.oid = nextCommit.oid
        repo.localBranches[branch] = try repo.commits(from: nextCommit.oid, since: nil).map { $0 as! MockCommit }
        repo.head = branch
        return commit as! MockCommit
    }

    func commitAndTag(repo: inout MockRepository, tagName: String) throws -> (MockCommit, MockTagReference) {
        let nextCommit = try commitAndSetHEAD(repo: &repo)
        let tag: MockTagReference = .annotated(name: tagName, tagging: nextCommit)
        repo.tags.append(tag)
        return (nextCommit, tag)
    }

    func testCreatingPrereleasesForVersion() throws {
        for channel in ReleaseChannel.prereleaseChannels {
            _ = try subtestCreatingPreleaseForVersion(channel: channel)

            let oldRepo = MockRepository.mock
            var repo = oldRepo
            _ = try commitAndTag(repo: &repo, tagName: "1.0.0-\(channel.rawValue).1")

            MockRepository.mock = repo
            _ = try subtestCreatingPreleaseForVersion(channel: channel, prereleaseBuild: "2")
            MockRepository.mock = oldRepo
        }

        let trainName = "test"
        Internal.loadTrains = { _ in
            [
                Trains.TrainImpl(
                    testName: trainName,
                    tagPrefix: nil,
                    linter: Trains.LinterSettingsImpl(
                        testProjectIdPrefix: "VPNAPPL-",
                        requireCommitTypes: [
                                "feat",
                                "fix",
                                "test",
                                "build",
                                "ci",
                        ]
                    ),
                    trailers: Trains.TrailersImpl(
                        testProjectId: "Project-Id"
                    )
                )
            ]
        }

        for channel in ReleaseChannel.prereleaseChannels {
            var invocation = try subtestCreatingPreleaseForVersion(train: trainName, channel: channel)
            let train = try invocation.parent.train?.get()

            let oldRepo = MockRepository.mock
            var repo = oldRepo
            _ = try commitAndTag(repo: &repo, tagName: "\(train?.tagPrefix ?? "")1.0.0-\(channel.rawValue).1")

            MockRepository.mock = repo
            _ = try subtestCreatingPreleaseForVersion(train: trainName, channel: channel, prereleaseBuild: "2")
            MockRepository.mock = oldRepo
        }
    }
}
