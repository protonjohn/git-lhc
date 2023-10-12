//
//  Created by John Biggs on 06.10.23.
//

import Foundation
import PackagePlugin

@main
struct Changelog: BuildToolPlugin {
    static let outputPathKey = "GLUON_CHANGELOG_OUTPUT_PATH"

    static var outputPath: String? {
        ProcessInfo.processInfo.environment[Self.outputPathKey]
    }

    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {

        let tool = try context.tool(named: "gluon")
        let path = Self.outputPath ?? "changelog.json"

        return [
            .buildCommand(
                displayName: "Gluon",
                executable: tool.path,
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

