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
    static var configuration = CommandConfiguration(subcommands: [Eval.self, Get.self])

    struct Options: ParsableArguments {
        @OptionGroup()
        var parent: LHC.Options

        @Option(
            name: [.customShort("D", allowingJoined: true), .customLong("define")],
            help: "Define a property to a value before interpreting the configuration."
        )
        var defines: [LHC.Define] = []

        @Option(
            name: .shortAndLong,
            help: "Include environment variables in the initial definitions matching the given glob."
        )
        var includeEnv: [String] = []

        @Flag(
            inversion: .prefixedNo,
            help: "Toggle value interpretation into types other than String."
        )
        var typedValues: Bool = true

        mutating func get() throws -> Configuration.IngestedConfig.Defines {
            guard let config = try parent.config?.get() else {
                throw ValidationError("Error fetching configuration file.")
            }

            // First, take the environment variables that have been explicitly included by the command line.
            let initialValues: Configuration.Defines = includeEnv.reduce(into: [:]) {
                for (key, value) in Internal.processInfo.environment {
                    guard (fnmatch($1, key, FNM_NOESCAPE)) == 0 else { continue }

                    $0[.init(rawValue: key)] = value
                }
            }

            // Then, take whatever command-line defines we have, and put them on top.
            let defines = defines.reduce(into: initialValues, {
                $0[$1.property] = $1.value
            })

            // Then, evaluate the state according to the passed train, channel, and the defined values.
            return try config.eval(train: parent.train, channel: parent.channel, define: defines)
        }
    }

    struct Eval: ParsableCommand {
        @OptionGroup()
        var parent: Config.Options

        @Flag(help: "Verify that the configuration file is sane, without evaluating it.")
        var checkOnly: Bool = false

        @Option(
            name: .shortAndLong,
            help: "Where to write the output file (defaults to stdout)."
        )
        var outputFile: String?

        mutating func run() throws {
            guard !checkOnly else {
                _ = try parent.parent.config?.get()
                return
            }

            let values = try parent.get()

            guard let outputFile = URL(string: outputFile ?? "/dev/stdout") else {
                throw ValidationError("Invalid path \(outputFile!).")
            }

            let decoder = JSONDecoder()
            let jsonDict = values.reduce(into: [String: Any]()) {
                let (key, value) = $1

                guard let value else { return }
                guard parent.typedValues else {
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
                        let object = try? decoder.decode(CodingDictionary.self, from: data) {
                        result = object.rawValue
                    } else {
                        result = value
                    }
                }

                $0[key.rawValue] = result
            }

            let handle = try FileHandle(forWritingTo: outputFile)
            let data = try JSONEncoder().encode(CodingDictionary(rawValue: jsonDict))
            try handle.write(contentsOf: data)
        }
    }

    struct Get: ParsableCommand {
        @OptionGroup()
        var parent: Config.Options

        @Argument(help: "The key to get from the configuration.")
        var key: String

        mutating func run() throws {
            let values = try parent.get()
            guard let value = values[key] else {
                throw ExitCode(1)
            }
            Internal.print(value)
        }
    }
}
