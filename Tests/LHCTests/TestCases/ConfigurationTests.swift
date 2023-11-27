//
//  ConfigurationTests.swift
//  
//
//  Created by John Biggs on 13.10.23.
//

import Foundation
import XCTest
import Yams

@testable import git_lhc

class ConfigurationTests: LHCTestCase {
    func testConfigFileCreated() throws {
        var createDefaultConfig = try CreateDefaultConfig.parse([])
        try createDefaultConfig.run()

        guard let contents = LHC.fileManager.contents(atPath: Self.configPath) else {
            XCTFail("No file exists at \(Self.configPath)")
            return
        }

        let decoder = YAMLDecoder()
        let config = try decoder.decode(Configuration.self, from: contents)

        XCTAssertEqual(config, Configuration.default)
    }

    func testExampleConfigParsesCorrectly() throws {
        let config = Configuration.example
        XCTAssertNotNil(config)
    }
}
