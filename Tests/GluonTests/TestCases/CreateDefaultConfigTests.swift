//
//  CreateDefaultConfigTests.swift
//  
//
//  Created by John Biggs on 13.10.23.
//

import Foundation
import XCTest
import Yams

@testable import gluon

class CreateDefaultConfigTests: GluonTestCase {
    func testConfigFileCreated() throws {
        var createDefaultConfig = try CreateDefaultConfig.parse([])
        try createDefaultConfig.run()

        guard let contents = Gluon.fileManager.contents(atPath: configPath) else {
            XCTFail("No file exists at \(configPath)")
            return
        }

        let decoder = YAMLDecoder()
        let config = try decoder.decode(Configuration.self, from: contents)

        XCTAssertEqual(config, Configuration.default)
    }
}
