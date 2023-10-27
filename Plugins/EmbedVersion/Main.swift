//
//  EmbedVersion.swift
//  
//
//  Created by John Biggs on 26.10.23.
//

import Foundation
import PackagePlugin

@main
struct EmbedVersion {
    static let trainNameKey = "GLUON_TRAIN_NAME"

    static var trainName: String? {
        ProcessInfo.processInfo.environment[Self.trainNameKey]
    }

    func createBuildCommands(toolPath: Path, trainName: String) throws -> [Command] {
        return [
            .buildCommand(
                displayName: "Gluon",
                executable: toolPath,
                arguments: [
                    "replace-versions",
                    "--train",
                    trainName
                ]
            )
        ]
    }
}

extension EmbedVersion: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let tool = try context.tool(named: "gluon")

        let trainName = Self.trainName ?? target.name
        return try createBuildCommands(toolPath: tool.path, trainName: trainName)
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension EmbedVersion: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        let tool = try context.tool(named: "gluon")

        let trainName = Self.trainName ?? target.displayName
        return try createBuildCommands(toolPath: tool.path, trainName: trainName)
    }
}

#endif
