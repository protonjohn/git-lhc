//
//  MockFileManagerTests.swift
//  
//
//  Created by John Biggs on 27.10.23.
//

import Foundation
import XCTest

class MockFileManagerTests: XCTestCase {
    var fileManager = MockFileManager.mock

    /*
     * Contents:
     *
     * /
     * /Users
     * /Users/test
     * /Users/test/repo
     * /Users/test/repo/.git (empty directory)
     * /Users/test/repo/.lhcconfig
     * /Users/test/repo/file (empty)
     */

    func testFileExists() {
        XCTAssert(fileManager.fileExists(atPath: "/Users/test/repo/file"))

        var isDir: Bool?
        XCTAssert(fileManager.fileExists(atPath: "/Users/test/repo/file", isDirectory: &isDir))
        XCTAssertEqual(isDir, false)

        isDir = nil
        XCTAssert(fileManager.fileExists(atPath: "/Users/test/repo/.git", isDirectory: &isDir))
        XCTAssertEqual(isDir, true)

        isDir = nil
        XCTAssert(fileManager.fileExists(atPath: "/Users/test/repo", isDirectory: &isDir))
        XCTAssertEqual(isDir, true)

        isDir = nil
        XCTAssert(fileManager.fileExists(atPath: "/Users/test/repo/", isDirectory: &isDir))
        XCTAssertEqual(isDir, true)
    }

    func testProperties() {
        XCTAssertEqual(fileManager.currentDirectoryPath, "/Users/test/repo")
        XCTAssertEqual(fileManager.homeDirectoryForCurrentUser.path(), "/Users/test")
    }

    func testContents() {
        XCTAssertNil(fileManager.contents(atPath: "/Users/test/repo/file"))
        XCTAssertNotNil(fileManager.contents(atPath: "/Users/test/repo/.lhcconfig"))
    }

    func testCreateAndRemove() throws {
        let contents = "hello, world!".data(using: .utf8)!
        let path = "/Users/test/repo/foo"

        XCTAssert(fileManager.createFile(atPath: path, contents: contents, attributes: [:]))

        var isDir: Bool? = nil
        XCTAssert(fileManager.fileExists(atPath: path, isDirectory: &isDir))
        XCTAssertEqual(isDir, false)

        XCTAssertEqual(fileManager.contents(atPath: path), contents)
        try fileManager.removeItem(atPath: path)

        isDir = nil
        XCTAssert(!fileManager.fileExists(atPath: path, isDirectory: &isDir))
        XCTAssertEqual(isDir, nil)
        XCTAssertNil(fileManager.contents(atPath: path))
    }
}
