//
//  EmbedTests.swift
//  
//
//  Created by John Biggs on 27.10.23.
//

import Foundation
import XCTest
import CodingCollection
import Yams
import LHCInternal
import LHC

@testable import LHC
@testable import LHCInternal
@testable import git_lhc

class EmbedTests: LHCTestCase {
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
                It has the short version SHORTVERSION.
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
            name: "version.yml",
            contents: try! YAMLEncoder().encode(structuredData).data(using: .utf8)
        )
    ]

    static let textReplacements: [Embed.Item: String] = [
        .shortVersion: "SHORTVERSION",
        .version: "FULLVERSION",
        .identifiers: "ALLIDENTIFIERS",
        .prerelease: "PRERELEASEIDENTIFIERS",
        .buildInfo: "BUILDIDENTIFIERS"
    ]

    static let structuredReplacements: [Embed.Item: String] = [
        .shortVersion: "CFBundleShortVersionString",
        .version: "CFBundleVersion",
        .buildInfo: "BuildIdentifiers",
        .identifiers: "Identifiers",
        .prerelease: "PrereleaseIdentifiers"
    ]

    static let structuredFormats: [Embed.Format] = [
        .plist,
        .json,
        .yaml
    ]

    func invoke(_ args: [String] = []) throws {
        var embed = try Embed.parse(args)
        try embed.run()
    }

    func verifyFileContents(
        expectFullVersion fullVersion: String,
        expectVersion version: String,
        expectIdentifiers identifiers: String,
        expectPrereleaseIdentifiers prereleaseIdentifiers: String,
        expectBuildIdentifiers buildIdentifiers: String
    ) throws {
        guard let textContents = Internal.fileManager.contents(atPath: "\(Self.repoPath)/version.txt"),
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

        guard let jsonContents = Internal.fileManager.contents(atPath: "\(Self.repoPath)/version.json"),
              let jsonCollection = try? JSONDecoder().decode(CodingCollection.self, from: jsonContents),
              case let .dictionary(jsonDict) = jsonCollection else {
            throw "No version file (or corrupted version file) at version.json"
        }

        guard let yamlContents = Internal.fileManager.contents(atPath: "\(Self.repoPath)/version.yml"),
              let yamlCollection = try? YAMLDecoder().decode(CodingCollection.self, from: yamlContents),
              case let .dictionary(yamlDict) = yamlCollection else {
            throw "No version file (or corrupted version file) at version.yml"
        }

        guard let plistContents = Internal.fileManager.contents(atPath: "\(Self.repoPath)/version.plist"),
              let plistCollection = try? PropertyListDecoder().decode(CodingCollection.self, from: plistContents),
              case let .dictionary(plistDict) = plistCollection else {
            throw "No version file (or corrupted version file) at version.plist"
        }

        for dict in [jsonDict, plistDict, yamlDict] {
            XCTAssertEqual(dict["CFBundleVersion"], .string(fullVersion))
            XCTAssertEqual(dict["CFBundleShortVersionString"], .string(version))
            XCTAssertEqual(dict["Identifiers"], .string(identifiers))
            XCTAssertEqual(dict["PrereleaseIdentifiers"], .string(prereleaseIdentifiers))
            XCTAssertEqual(dict["BuildIdentifiers"], .string(buildIdentifiers))
        }
    }

    func replaceAll(forcedVersion: String? = nil) throws {
        for format in Embed.Format.allCases {
            for portion in Embed.Item.allCases {
                let identifier: String

                if format == .text {
                    identifier = Self.textReplacements[portion]!
                } else {
                    identifier = Self.structuredReplacements[portion]!
                }

                var arguments = [
                    "--train", "test",
                    "-f", "version.\(format.fileExtension)",
                    "--identifier", identifier,
                    "--portion", portion.rawValue
                ]
                if let forcedVersion {
                    arguments.append(forcedVersion)
                }
                try invoke(arguments)
            }
        }
    }

    func testReplaceVersionsWithDerivedVersion() throws {
        for file in Self.versionFiles {
            guard case .file(let name, let contents) = file else {
                fatalError("Test invariant error")
            }

            let filePath = "\(Self.repoPath)/\(name)"
            guard Internal.fileManager.createFile(
                atPath: filePath,
                contents: contents,
                attributes: [:]
            ) else {
                XCTFail("Could not create file at \(filePath)")
                return
            }
        }

        let fileManager = Internal.fileManager // save FM state

        Configuration.getConfig = { _ in
            try? .success(.init(parsing: """
            train = test
            """))
        }

        try replaceAll()

        try verifyFileContents(
            expectFullVersion: "0.1.0",
            expectVersion: "0.1.0",
            expectIdentifiers: "",
            expectPrereleaseIdentifiers: "",
            expectBuildIdentifiers: ""
        )

        Internal.fileManager = fileManager // restore FM state

        try replaceAll(forcedVersion: "1.2.3-rc.3.foo+202310271643.Friday")

        try verifyFileContents(
            expectFullVersion: "1.2.3-rc.3.foo+202310271643.Friday",
            expectVersion: "1.2.3",
            expectIdentifiers: "rc.3.foo+202310271643.Friday",
            expectPrereleaseIdentifiers: "rc.3.foo",
            expectBuildIdentifiers: "202310271643.Friday"
        )
    }
}
