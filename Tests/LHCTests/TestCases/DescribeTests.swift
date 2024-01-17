//
//  DescribeTests.swift
//  
//
//  Created by John Biggs on 13.10.23.
//

import Foundation
import XCTest
import Version
import SwiftGit2

@testable import LHC
@testable import LHCInternal
@testable import git_lhc

class DescribeReleaseTests: LHCTestCase {
    let decoder = JSONDecoder()

    func invoke(_ args: [String] = []) throws {
        var changelog = try Describe.parse(args)
        try changelog.run()
    }

    /// Tests the case where no version tags exist in the repository yet.
    func testBootstrapping() throws {
        try setBranch(.branchOffOfEarlyDevelop)
        try invoke(["--format", "json", "--dry-run"])

        XCTAssertEqual(errorOutput, "")

        let data = testOutput.data(using: .utf8) ?? Data()
        let releases = try decoder.decode([Release].self, from: data)
        XCTAssertEqual(releases.count, 1)
        XCTAssertEqual(releases.first?.version, Version(0, 0, 1))

        let fixes = releases.first?.changes["fix"]
        let features = releases.first?.changes["feat"]

        XCTAssertEqual(fixes?.first?.summary, "third commit")
        XCTAssertEqual(fixes?.count, 1)

        XCTAssertEqual(features?.first?.summary, "second commit")
        XCTAssertEqual(features?.second?.summary, "initial commit")
        XCTAssertEqual(features?.count, 2)
    }

    /// Tests the user requesting the changelog entry for a specific version.
    func testSpecificVersion() throws {
        try invoke(["--format", "json", "--show", "0.0.1"])

        XCTAssertEqual(errorOutput, "")

        let data = testOutput.data(using: .utf8) ?? Data()
        let releases = try decoder.decode([Release].self, from: data)
        XCTAssertEqual(releases.count, 1)
        XCTAssertEqual(releases.first?.version, Version(0, 0, 1))
        XCTAssertEqual(releases.first?.tagName, "0.0.1")

        XCTAssertEqual(releases.first?.changes.count, 2)
        let fixes = releases.first?.changes["fix"]
        let features = releases.first?.changes["feat"]

        XCTAssertEqual(fixes?.first?.summary, "more fixes")
        XCTAssertEqual(fixes?.second?.summary, "third commit")
        XCTAssertEqual(fixes?.count, 2)

        XCTAssertEqual(features?.first?.summary, "second commit")
        XCTAssertEqual(features?.second?.summary, "initial commit")
        XCTAssertEqual(features?.count, 2)
    }

    func testShowingNewReleaseWithBreakingChange() throws {
        try invoke(["--format", "json", "--dry-run"])

        XCTAssertEqual(errorOutput, "")

        let data = testOutput.data(using: .utf8) ?? Data()
        let releases = try decoder.decode([Release].self, from: data)
        XCTAssertEqual(releases.count, 1)

        XCTAssertEqual(releases.first?.version, Version(1, 0, 0))
        XCTAssertEqual(releases.first?.tagName, nil)

        XCTAssertEqual(releases.first?.changes.count, 1)
        let build = releases.first?.changes["build"]

        XCTAssertEqual(build?.count, 1)
        XCTAssertEqual(build?.first?.summary, "integrate library 3.2.1")
    }

    /// Tests the user requesting the changelog entry for a prerelease version.
    /// The changelog should display the changes for that prerelease version since the last prod release, and not the changes since the last prerelease version.
    func testSpecificPrereleaseVersion() throws {
        let tag: MockTagReference = .secondPrerelease
        try invoke(["--format", "json", "--show", tag.name])

        XCTAssertEqual(errorOutput, "")

        let data = testOutput.data(using: .utf8) ?? Data()
        let releases = try decoder.decode([Release].self, from: data)
        XCTAssertEqual(releases.count, 1)
        XCTAssertEqual(releases.first?.version, Version(tag.name))
        XCTAssertEqual(releases.first?.tagName, tag.name)

        XCTAssertEqual(releases.first?.changes.count, 1)
        let fix = releases.first?.changes["fix"]

        XCTAssertEqual(fix?.count, 2)
        XCTAssertEqual(fix?.first?.summary, "this is another prerelease commit")
        XCTAssertEqual(fix?.second?.summary, "this is the first prerelease commit")
    }

    /// Tests printing the entire changelog.
    func testMultipleVersions() throws {
        try invoke(["--format", "json", "--show", "all", "--dry-run"])

        XCTAssertEqual(errorOutput, "")

        let data = testOutput.data(using: .utf8) ?? Data()
        let releases = try decoder.decode([Release].self, from: data)
        XCTAssertEqual(releases.count, 4)

        do {
            let release = releases.first
            XCTAssertEqual(release?.version, Version(1, 0, 0))
            XCTAssertEqual(release?.tagName, nil)
        }

        do {
            let release = releases.second
            XCTAssertEqual(release?.version, Version(0, 1, 0))
            XCTAssertEqual(release?.tagName, "0.1.0")
        }

        do {
            guard releases.count == 4 else {
                XCTFail("Incorrect release count")
                return
            }
            let release = releases[2]
            XCTAssertEqual(release.version, Version(0, 0, 2))
            XCTAssertEqual(release.tagName, "0.0.2")
        }

        do {
            guard releases.count == 4 else {
                XCTFail("Incorrect release count")
                return
            }
            let release = releases[3]
            XCTAssertEqual(release.version, Version(0, 0, 1))
            XCTAssertEqual(release.tagName, "0.0.1")
        }
    }

    /// Tests printing the "latest" version, but it's already been tagged.
    func testLatestNoVersionBump() throws {
        try setBranch(.hotfix)
        try invoke(["--format", "json"])

        XCTAssertEqual(errorOutput, "")

        let data = testOutput.data(using: .utf8) ?? Data()
        let releases = try decoder.decode([Release].self, from: data)
        XCTAssertEqual(releases.count, 1)

        XCTAssertEqual(releases.first?.version, Version(0, 0, 2))
        XCTAssertEqual(releases.first?.tagName, "0.0.2")
        XCTAssertEqual(releases.first?.changes.count, 1)

        let fixes = releases.first?.changes["fix"]
        XCTAssertEqual(fixes?.first?.summary, "hotfix off of a non-develop branch")
        XCTAssertEqual(fixes?.count, 1)
    }

    /// Tests the changelog finds versions properly when using a train/tag prefix.
    func testDescribeReleaseWithTagPrefix() throws {
        Configuration.getConfig = { _ in
            try? .success(.init(parsing: """
            train = test
            tag_prefix = train/
            commit_categories = ["feat", "fix", "test", "build", "ci"]
            """))
        }

        let subtests = [
            subtestDescribeReleaseWithTagPrefixSpecificVersion
        ]

        for subtest in subtests {
            try subtest()
            Internal.shell = MockShell.mock
        }
    }

    func subtestDescribeReleaseWithTagPrefixSpecificVersion() throws {
        try invoke(["--format", "json", "--show", "0.1.0", "--train", "test"])

        XCTAssertEqual(errorOutput, "")

        let data = testOutput.data(using: .utf8) ?? Data()
        let releases = try decoder.decode([Release].self, from: data)
        XCTAssertEqual(releases.count, 1)
        XCTAssertEqual(releases.first?.version, Version(0, 1, 0))
        XCTAssertEqual(releases.first?.tagName, "train/0.1.0")

        let fixes = releases.first?.changes["fix"]
        let features = releases.first?.changes["feat"]

        XCTAssertEqual(fixes?.count, 1)
        XCTAssertEqual(fixes?.first?.summary, "third commit")

        XCTAssertEqual(features?.count, 2)
        XCTAssertEqual(features?.first?.summary, "second commit")
        XCTAssertEqual(features?.second?.summary, "initial commit")
    }
}
