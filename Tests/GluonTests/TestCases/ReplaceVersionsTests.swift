//
//  ReplaceVersionsTests.swift
//  
//
//  Created by John Biggs on 27.10.23.
//

import Foundation
import XCTest
import CodingCollection
import Yams

@testable import gluon

class ReplaceVersionsTests: GluonTestCase {
    static let structuredData: CodingCollection = [
        "CFBundleVersion": "Version",
        "CFBundleShortVersionString": "VersionString",
        "BuildIdentifiers": "Foo",
        "Irrelevant key": 2,
        "CFBundleExplodes": true,
        "InnerList": [ "hello", "world", 2, 3, true, 3.14159 ]
        // leave some missing to see how it handles missing keys
    ]

    static let versionFiles: [MockFileManager.MockFile] = [
        .file(
            name: "version.txt",
            contents: """
                This is version FULLVERSION.
                It has the short version VERSION.
                It has identifiers ALLIDENTIFIERS.
                It has prerelease identifiers PRERELEASEIDENTIFIERS.
                It has build identifiers BUILDIDENTIFIERS.
                """.data(using: .utf8)
        ),
        .file(
            name: "version.plist",
            contents: try! PropertyListEncoder().encode(structuredData)
        ),
        .file(
            name: "version.json",
            contents: try! JSONEncoder().encode(structuredData)
        ),
        .file(
            name: "version.yaml",
            contents: try! YAMLEncoder().encode(structuredData).data(using: .utf8)
        )
    ]

    static let textReplacements: [(String, Configuration.VersionReplacementItem?)] = [
        ("FULLVERSION", nil),
        ("VERSION", .version),
        ("ALLIDENTIFIERS", .identifiers),
        ("PRERELEASEIDENTIFIERS", .prereleaseIdentifiers),
        ("BUILDIDENTIFIERS", .buildIdentifiers)
    ]

    static let structuredReplacements: [(String, Configuration.VersionReplacementItem?)] = [
        ("CFBundleShortVersionString", .fullVersion),
        ("CFBundleVersion", .version),
        ("BuildIdentifiers", .buildIdentifiers),
        ("Identifiers", .identifiers),
        ("PrereleaseIdentifiers", .prereleaseIdentifiers)
    ]

    static let structuredFormats: [Configuration.VersionReplacementFormat] = [
        .plist,
        .json,
        .yaml
    ]

    static let config: Configuration = .init(
        projectPrefix: nil,
        projectIdTrailerName: nil,
        jiraReleaseNotesField: nil,
        subjectMaxLineLength: nil,
        bodyMaxLineLength: nil,
        branchNameLinting: nil,
        commitCategories: nil,
        trains: [
            .init(
                name: "test",
                displayName: nil,
                tagPrefix: nil,
                replace: textReplacements.map {
                    .init(key: $0.0, file: "version.txt", item: $0.1, format: nil)
                } + structuredFormats.flatMap { format in
                    structuredReplacements.map {
                        .init(key: $0.0, file: "version.\(format)", item: $0.1, format: format)
                    }
                }
            )
        ]
    )

    func invoke(_ args: [String] = []) throws {
        let replaceVersions = try ReplaceVersions.parse(args)
        try replaceVersions.run()
    }

    func verifyFileContents(
        expectFullVersion fullVersion: String,
        expectVersion version: String,
        expectIdentifiers identifiers: String,
        expectPrereleaseIdentifiers prereleaseIdentifiers: String,
        expectBuildIdentifiers buildIdentifiers: String
    ) throws {
        guard let textContents = Gluon.fileManager.contents(atPath: "\(Self.repoPath)/version.txt"),
              let textFile = String(data: textContents, encoding: .utf8) else {
            throw "No version file at version.txt"
        }

        XCTAssertEqual(textFile, """
            This is version \(fullVersion).
            It has the short version \(version).
            It has identifiers \(identifiers).
            It has prerelease identifiers \(prereleaseIdentifiers).
            It has build identifiers \(buildIdentifiers).
            """)

        guard let jsonContents = Gluon.fileManager.contents(atPath: "\(Self.repoPath)/version.json"),
              let jsonCollection = try? JSONDecoder().decode(CodingCollection.self, from: jsonContents),
              case let .dictionary(jsonDict) = jsonCollection else {
            throw "No version file (or corrupted version file) at version.json"
        }

        guard let yamlContents = Gluon.fileManager.contents(atPath: "\(Self.repoPath)/version.yaml"),
              let yamlCollection = try? YAMLDecoder().decode(CodingCollection.self, from: yamlContents),
              case let .dictionary(yamlDict) = yamlCollection else {
            throw "No version file (or corrupted version file) at version.yaml"
        }

        guard let plistContents = Gluon.fileManager.contents(atPath: "\(Self.repoPath)/version.plist"),
              let plistCollection = try? PropertyListDecoder().decode(CodingCollection.self, from: plistContents),
              case let .dictionary(plistDict) = plistCollection else {
            throw "No version file (or corrupted version file) at version.plist"
        }

        for dict in [jsonDict, plistDict, yamlDict] {
            XCTAssertEqual(dict["CFBundleVersion"], .string(version))
            XCTAssertEqual(dict["CFBundleShortVersionString"], .string(fullVersion))
            XCTAssertEqual(dict["Identifiers"], .string(identifiers))
            XCTAssertEqual(dict["PrereleaseIdentifiers"], .string(prereleaseIdentifiers))
            XCTAssertEqual(dict["BuildIdentifiers"], .string(buildIdentifiers))
        }
    }

    func testReplaceVersionsWithDerivedVersion() throws {
        for file in Self.versionFiles {
            guard case .file(let name, let contents) = file else {
                fatalError("Test invariant error")
            }

            let filePath = "\(Self.repoPath)/\(name)"
            guard Gluon.fileManager.createFile(
                atPath: filePath,
                contents: contents,
                attributes: [:]
            ) else {
                XCTFail("Could not create file at \(filePath)")
                return
            }
        }

        let fileManager = Gluon.fileManager // save FM state

        Configuration.configuration = Self.config

        try invoke(["--train", "test"])

        try verifyFileContents(
            expectFullVersion: "0.1.0",
            expectVersion: "0.1.0",
            expectIdentifiers: "",
            expectPrereleaseIdentifiers: "",
            expectBuildIdentifiers: ""
        )

        Gluon.fileManager = fileManager // restore FM state

        try invoke(["--train", "test", "1.2.3-rc.3.foo+202310271643.Friday"])

        try verifyFileContents(
            expectFullVersion: "1.2.3-rc.3.foo+202310271643.Friday",
            expectVersion: "1.2.3",
            expectIdentifiers: "rc.3.foo+202310271643.Friday",
            expectPrereleaseIdentifiers: "rc.3.foo",
            expectBuildIdentifiers: "202310271643.Friday"
        )
    }
}
