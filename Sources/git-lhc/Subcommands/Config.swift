//
//  Config.swift
//  
//
//  Created by John Biggs on 28.11.23.
//

import Foundation
import ArgumentParser

import LHC
import LHCInternal

struct Config: ParsableCommand {
    static var configuration = CommandConfiguration(subcommands: [ConfigEval.self])
}

struct ConfigEval: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "eval")

    static var fileManager: FileManager = .default
    static var processInfo: ProcessInfo = .processInfo

    @OptionGroup()
    var parent: LHC.Options

    @Option(
        name: .shortAndLong,
        help: "Include environment variables in the initial definitions matching the given glob."
    )
    var includeEnv: [String] = []

    @Flag(help: "Verify that the configuration file is sane, without evaluating it.")
    var checkOnly: Bool = false

    @Flag(
        inversion: .prefixedNo,
        help: "If using with '--format json', toggles value interpretation into types other than String."
    )
    var typedValues: Bool = true

    @Option(
        name: .shortAndLong,
        help: "Where to write the output file (defaults to stdout)."
    )
    var outputFile: String?

    @Option(
        name: [.customShort("D", allowingJoined: true), .long],
        help: "Define a property to a value before interpreting the file."
    )
    var defines: [Define] = []

    mutating func run() throws {
        guard let config = parent.config else {
            throw ValidationError("Error in configuration file.")
        }

        guard !checkOnly else {
            return
        }

        // First, take the environment variables that have been explicitly included by the command line.
        let initialValues: Configuration.Defines = includeEnv.reduce(into: [:]) {
            for (key, value) in Self.processInfo.environment {
                guard (fnmatch($1, key, FNM_NOESCAPE)) == 0 else { continue }

                $0[.init(rawValue: key)] = value
            }
        }

        // Then, take whatever command-line defines we have, and put them on top.
        let defines = defines.reduce(into: initialValues, {
            $0[$1.property] = $1.value
        })

        // Then, evaluate the state according to the passed train, channel, and the defined values.
        let values = try config.eval(train: parent.train, channel: parent.channel, define: defines)

        guard let outputFile = URL(string: outputFile ?? "/dev/stdout") else {
            throw ValidationError("Invalid path \(outputFile!).")
        }

        let jsonDict = values.reduce(into: [String: Any]()) {
            let (key, value) = $1

            guard let value else { return }
            guard typedValues else {
                $0[key.rawValue] = value
                return
            }

            let result: Any
            switch value {
            case "true", "YES":
                result = true
            case "false", "NO":
                result = false
            default:
                if let int = Int(value) {
                    result = int
                } else if let double = Double(value) {
                    result = double
                } else if value.couldBeJSON,
                    let data = value.data(using: .utf8),
                    let object = try? JSONSerialization.jsonObject(with: data) {
                    result = object
                } else {
                    result = value
                }
            }

            $0[key.rawValue] = result
        }

        let handle = try FileHandle(forWritingTo: outputFile)
        let data = try JSONSerialization.data(withJSONObject: jsonDict)
        try handle.write(contentsOf: data)
    }
}

struct Define: ExpressibleByArgument {
    public let property: Configuration.Property
    public let value: String
}

extension Define {
    init?(argument: String) {
        let components = argument.split(separator: "=", maxSplits: 1)

        self.init(
            property: .init(rawValue: String(components.first!)),
            value: components.count > 1 ? String(components[1]) : "YES"
        )
    }
}
