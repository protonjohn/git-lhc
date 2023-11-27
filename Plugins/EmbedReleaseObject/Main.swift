//
//  Created by John Biggs on 06.10.23.
//

import Foundation
import PackagePlugin

@main
struct EmbedReleaseObject {
    static let objectNameKey = "RELEASE_OBJECT_NAME"
    static var objectName: String? {
        ProcessInfo.processInfo.environment[Self.objectNameKey]
    }

    func createBuildCommands(
        lhc: Path,
        plistutil: Path,
        workDirectory: Path
    ) throws -> [Command] {
        let objectName = Self.objectName ?? "ReleaseDescription"
        let plistPath = workDirectory.appending("\(objectName).plist")
        let sourcePath = workDirectory.appending("\(objectName).swift")

        return [
            .buildCommand(
                displayName: "Describe current version",
                executable: lhc,
                arguments: [
                    "describe-release",
                    "--format", "plist",
                    "--show", "all",
                    "-o",
                    plistPath.string
                ],
                outputFiles: [plistPath]
            ),
            .buildCommand(
                displayName: "Generate release object",
                executable: plistutil,
                arguments: [
                    "convert",
                    "--input-format",
                    "plist",
                    "--output-format",
                    "swift",
                    "-o",
                    sourcePath.string,
                    plistPath.string
                ],
                inputFiles: [plistPath],
                outputFiles: [sourcePath]
            )
        ]
    }
}

extension EmbedReleaseObject: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let lhc = try context.tool(named: "lhc")
        let plistutil = try context.tool(named: "plistutil")
        let outputDirectory = context.pluginWorkDirectory.appending("GeneratedFiles")

        return try createBuildCommands(
            lhc: lhc.path,
            plistutil: plistutil.path,
            workDirectory: outputDirectory
        )
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension EmbedReleaseObject: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        let lhc = try context.tool(named: "lhc")
        let plistutil = try context.tool(named: "plistutil")
        let outputDirectory = context.pluginWorkDirectory.appending("GeneratedFiles")

        return try createBuildCommands(
            lhc: lhc.path,
            plistutil: plistutil.path,
            workDirectory: outputDirectory
        )
    }
}

#endif

