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
    static let configuration = CommandConfiguration(
        abstract: "Create a default configuration file at the specified path."
    )

    @Argument()
    var configPath: String = ".gluon.yml"

    mutating func run() throws {
        if !configPath.starts(with: "/") {
            configPath = "\(Gluon.fileManager.currentDirectoryPath)/\(configPath)"
        }

        if Gluon.fileManager.fileExists(atPath: configPath) {
            guard Gluon.promptForConfirmation("File at \(configPath) already exists.") else {
                throw CreateDefaultConfigError.userAborted
            }

            try Gluon.fileManager.removeItem(atPath: configPath)
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

enum CreateDefaultConfigError: String, Error {
    case userAborted = "User aborted."
}
