//
//  EmbedVersion.swift
//  
//
//  Created by John Biggs on 26.10.23.
//

import Foundation
import PackagePlugin

struct EmbedVersion {
    static let outputPathKey = "GLUON_CHANGELOG_OUTPUT_PATH"

    static var outputPath: String? {
        ProcessInfo.processInfo.environment[Self.outputPathKey]
    }

    func createBuildCommands(toolPath: Path) throws -> [Command] {
        let path = Self.outputPath ?? "changelog.json"

        return [
            .buildCommand(
                displayName: "Gluon",
                executable: toolPath,
                arguments: [
                    "changelog",
                    "--format", "json",
                    "--show", "all",
                    "-o", path
                ]
            )
        ]
    }
}

extension EmbedVersion: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let tool = try context.tool(named: "gluon")
        return try createBuildCommands(toolPath: tool.path)
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension EmbedVersion: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        let tool = try context.tool(named: "gluon")
        let files = target.inputFiles.filter { $0.path.lastComponent == "Info.plist" }
        return try createBuildCommands(toolPath: tool.path)
    }
}

#endif
