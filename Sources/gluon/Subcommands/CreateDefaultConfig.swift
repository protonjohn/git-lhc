//
//  File.swift
//  
//
//  Created by John Biggs on 13.10.23.
//

import Foundation
import ArgumentParser
import Yams

struct CreateDefaultConfig: ParsableCommand {
    @Argument()
    var configPath: String = ".gluon.yml"

    mutating func run() throws {
        if !configPath.starts(with: "/") {
            configPath = "\(Gluon.fileManager.currentDirectoryPath)/\(configPath)"
        }

        let encoder = YAMLEncoder()
        let config = try encoder.encode(Configuration.default)
        guard Gluon.fileManager.createFile(
            atPath: configPath,
            contents: config.data(using: .utf8)
        ) else {
            throw GluonError.invalidPath(configPath)
        }
    }
}
