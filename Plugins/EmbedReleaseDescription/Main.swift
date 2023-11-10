//
//  Created by John Biggs on 06.10.23.
//

import Foundation
import PackagePlugin

@main
struct EmbedReleaseDescription {
    static let outputPathKey = "GLUON_RELEASE_INFO_OUTPUT_PATH"

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
                    "describe-release",
                    "--format", "json",
                    "--show", "all",
                    "-o", path
                ]
            )
        ]
    }
}

extension EmbedReleaseDescription: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let tool = try context.tool(named: "gluon")
        return try createBuildCommands(toolPath: tool.path)
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension EmbedReleaseDescription: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        let tool = try context.tool(named: "gluon")
        return try createBuildCommands(toolPath: tool.path)
    }
}

#endif
