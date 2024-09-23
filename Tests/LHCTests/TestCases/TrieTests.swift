//
//  TrieTests.swift
//
//
//  Created by John Biggs on 09.07.2024.
//

import Foundation
import XCTest
@testable import LHCInternal

class TrieTests: XCTestCase {
    func testCharTries() {
        var t = Trie<Character>()

        t.insert(string: "He")
        t.insert(string: "Hell")
        t.insert(string: "Hello")
        t.insert(string: "Beelzebub")

        XCTAssertEqual(t.maxPrefix, 4)
        XCTAssertEqual(t.count, 4)
    }

    func testIntTries() {
        var t = Trie<UInt8>()

        t.insert([12, 23, 42, 15])
        t.insert([12, 23, 42, 15, 64, 128, 255])
        t.insert([12, 23, 42, 15, 16])
        t.insert([1, 2, 3, 4, 5, 6])
        
        XCTAssertEqual(t.maxPrefix, 4)
        XCTAssertEqual(t.count, 4)
    }

    func testUUIDTries() {
        var t = Trie<UInt8>()

        var uuid1 = UUID().uuid
        do {
            let bytes = withUnsafeBytes(of: &uuid1) { Array($0) }
            t.insert(bytes)
            t.insert(bytes) // insert a second time to make sure prefix stays at 0
        }

        XCTAssertEqual(t.maxPrefix, 0)
        XCTAssertEqual(t.count, 2)
    }
}
