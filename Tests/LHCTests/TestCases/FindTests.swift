//
//  FindVersionsTests.swift
//  
//
//  Created by John Biggs on 26.10.23.
//

import Foundation
import XCTest
import ArgumentParser

@testable import LHC
@testable import git_lhc

class FindVersionsTests: LHCTestCase {
    var decoder: JSONDecoder {
        JSONDecoder()
    }

    func invoke(_ args: [String] = []) throws {
        var findVersions = try Find.parse(args)
        try findVersions.run()
    }

    override func invokeTest() {
        let value = Configuration.getConfig
        Configuration.getConfig = { _ in
            try? Configuration(parsing: """
            project_id_prefix = TEST-
            project_id_trailer = Project-Id
            """)
        }

        super.invokeTest()

        Configuration.getConfig = value
    }

    func testFindingTaskIdWithPrefix() throws {
        try invoke(["--format", "json", "TEST-8192"])

        XCTAssertEqual(errorOutput, "")
        let data = testOutput.data(using: .utf8) ?? Data()
        let releases = try decoder.decode([Release].self, from: data)
        XCTAssertEqual(releases.count, 1)

        guard let release = releases.first else {
            XCTFail("No releases were found.")
            return
        }

        XCTAssertEqual(release.version?.description, "0.0.1")
    }

    func testFindingTaskIdNotPartOfRelease() throws {
        do {
            try invoke(["--format", "json", "TEST-1234"])
            XCTFail("Invocation should have failed.")
        } catch {
            guard let error = error as? ExitCode else {
                XCTFail("Did not fail with exit code")
                return
            }

            XCTAssertEqual(error.rawValue, 1)
            XCTAssertEqual(errorOutput, "")
            XCTAssertEqual(
                testOutput.trimmingCharacters(in: .whitespacesAndNewlines),
                "No releases with the specified task ID were found."
            )
        }
    }

   func testFindingTaskIdWithoutPrefix() throws {
        try invoke(["--format", "json", "8192"])

        XCTAssertEqual(errorOutput, "")
        let data = testOutput.data(using: .utf8) ?? Data()
        let releases = try decoder.decode([Release].self, from: data)
        XCTAssertEqual(releases.count, 1)

        guard let release = releases.first else {
            XCTFail("No releases were found.")
            return
        }

        XCTAssertEqual(release.version?.description, "0.0.1")
    }

    func testFindingNonexistentTaskId() throws {
        do {
            try invoke(["--format", "json", "FUBAR-420"])
            XCTFail("Invocation should have failed.")
        } catch {
            guard let error = error as? ExitCode else {
                XCTFail("Did not fail with exit code")
                return
            }

            XCTAssertEqual(error.rawValue, 1)
            XCTAssertEqual(errorOutput, "")
            XCTAssertEqual(
                testOutput.trimmingCharacters(in: .whitespacesAndNewlines),
                "No releases with the specified task ID were found."
            )
        }
    }
}
