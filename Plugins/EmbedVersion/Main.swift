//
//  EmbedVersion.swift
//  
//
//  Created by John Biggs on 26.10.23.
//

import Foundation
import PackagePlugin

enum BuildEnvironmentVariables: String {
    private static var environment = ProcessInfo.processInfo.environment

    /// If not defined, defaults to the Swift module name or Xcode target name.
    case trainName = "GLUON_TRAIN_NAME"
    /// A comma-separated list of extra build identifiers to add to the embedded version number.
    case extraBuildIdentifiers = "GLUON_BUILD_IDENTIFIERS"

    var value: String? {
        Self.environment[rawValue]
    }
}

@main
struct EmbedVersion {

    func createBuildCommands(toolPath: Path, trainName: String) throws -> [Command] {
        let identifiers = BuildEnvironmentVariables.extraBuildIdentifiers.value?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var buildArguments: [String] = []
        if let identifiers {
            buildArguments.append("--build-identifiers")
            buildArguments.append(contentsOf: identifiers)
        }

        return [
            .buildCommand(
                displayName: "Gluon",
                executable: toolPath,
                arguments: [
                    "replace-versions",
                    "--train",
                    trainName
                ] + buildArguments
            )
        ]
    }
}

extension EmbedVersion: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let tool = try context.tool(named: "gluon")

        let trainName = BuildEnvironmentVariables.trainName.value ?? target.name
        return try createBuildCommands(toolPath: tool.path, trainName: trainName)
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension EmbedVersion: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        let tool = try context.tool(named: "gluon")

        let trainName = BuildEnvironmentVariables.trainName.value ?? target.displayName
        return try createBuildCommands(toolPath: tool.path, trainName: trainName)
    }
}

#endif
