//
//  ReplaceVersions.swift
//  
//
//  Created by John Biggs on 27.10.23.
//

import Foundation
import ArgumentParser
import Yams
import Version
import SwiftGit2
import LHC
import LHCInternal

struct Embed: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Modify the version files for the configured train according to the current version."
    )

    @OptionGroup()
    var parent: LHC.Options

    @Flag(
        name: .shortAndLong,
        help: """
            Replace versions as if a new release were being created. \
            If --channel is specified, then that channel will be used for calculating the version number.
            """
    )
    var dryRun: Bool = false

    @Option(
        name: .shortAndLong,
        parsing: .upToNextOption,
        help: "Additional build metadata identifiers to add to the version tag being replaced."
    )
    var buildIdentifiers: [String] = []

    @Option(
        name: [.customShort("f"), .customLong("file")],
        help: "The version file containing the key or identifier needing replacement."
    )
    var versionFilePath: String

    @Option(
        name: .customLong("format"),
        help: """
        The format of the version file, if it can't be determined from the extension. \
        Possible values are \(Format.possibleValues).
        """
    )
    var commandLineFormat: Format?

    @Option(help: "How much of the version to include. Possible values are \(Item.possibleValues).")
    var portion: Item = .version

    @Option(help: """
        If the format is plaintext, the string to replace. Otherwise, the key under which to store the version.
        """
    )
    var identifier: String = "VERSION"

    @Argument(
        help: "If specified, ignore the git history and force the version to a particular value.",
        transform: { (versionString: String) throws -> Version in
            guard let version = Version(versionString) else {
                throw NewError.invalidVersion(versionString)
            }

            return version
        }
    )
    var forcedVersion: Version? = nil

    lazy var resolvedURL: URL? = {
        let baseURL = URL(filePath: parent.repo, directoryHint: .isDirectory)
        guard let url = URL(string: versionFilePath, relativeTo: baseURL) else {
            return nil
        }

        return url.absoluteURL
    }()

    lazy var format: Format? = {
        if let commandLineFormat {
            return commandLineFormat
        }

        guard let resolvedURL else {
            return nil
        }

        return Format(fileExtension: resolvedURL.pathExtension)
    }()

    mutating func validate() throws {
        guard let resolvedURL, Internal.fileManager.fileExists(atPath: resolvedURL.path()) else {
            throw ValidationError("No file exists at \(resolvedURL?.path() ?? "(nil)").")
        }

        guard format != nil else {
            throw ValidationError("Specified file has no extension, and --format was not specified.")
        }
    }

    func decode(contents: Data, format: Format) throws -> [String: Any] {
        let versionFile: CodingDictionary
        switch format {
        case .json:
            versionFile = try JSONDecoder()
                .decode(type(of: versionFile), from: contents)
        case .yaml:
            versionFile = try YAMLDecoder()
                .decode(type(of: versionFile), from: contents)
        case .plist:
            versionFile = try PropertyListDecoder()
                .decode(type(of: versionFile), from: contents)
        default:
            fatalError("Unsupported format \(format)")
        }
        return versionFile.rawValue
    }

    func encode(dictionary: [String: Any], format: Format) throws -> Data? {
        let versionFile = CodingDictionary(rawValue: dictionary)
        let result: StringOrData
        switch format {
        case .json:
            result = try .init(JSONEncoder().encode(versionFile))
        case .yaml:
            result = try .init(YAMLEncoder().encode(versionFile))
        case .plist:
            result = try .init(PropertyListEncoder().encode(versionFile))
        default:
            fatalError("Unsupported format \(format)")
        }

        return result.data
    }

    func replaceStructured(
        contents: inout Data,
        key: String,
        value: String,
        format: Format
    ) throws {
        var dictionary = try decode(contents: contents, format: format)
        dictionary[key] = value
        guard let encoded = try encode(dictionary: dictionary, format: format) else {
            throw ReplaceVersionsError.encodingError
        }

        contents = encoded
    }

    func replaceText(
        contents: inout Data,
        replace text: String,
        with value: String
    ) throws {
        guard let replacementText = text.data(using: .utf8) else {
            throw ReplaceVersionsError.encodingError
        }
        guard let replacementValue = value.data(using: .utf8) else {
            throw ReplaceVersionsError.encodingError
        }

        contents.replace(replacementText, with: replacementValue)
    }

    mutating func replace(in repo: inout Repositoryish, with version: Version) throws {
        let path = resolvedURL!.path()

        let value: String
        switch portion {
        case .version:
            value = version.description
        case .shortVersion:
            value = version.shortVersion.description
        case .identifiers:
            var result = version.prereleaseIdentifiers.joined(separator: ".")
            if !result.isEmpty {
                let build = version.buildMetadataIdentifiers.joined(separator: ".")
                result += "+\(build)"
            }
            value = result
        case .prerelease:
            value = version.prereleaseIdentifiers.joined(separator: ".")
        case .buildInfo:
            value = version.buildMetadataIdentifiers.joined(separator: ".")
        }

        guard var contents = Internal.fileManager.contents(atPath: path) else {
            throw ReplaceVersionsError.noSuchFile(at: path)
        }

        if format?.isStructured == true {
            try replaceStructured(
                contents: &contents,
                key: identifier,
                value: value,
                format: format!
            )
        } else {
            try replaceText(
                contents: &contents,
                replace: identifier,
                with: value
            )
        }

        try Internal.fileManager.removeItem(atPath: path)
        guard Internal.fileManager.createFile(atPath: path, contents: contents) else {
            throw ReplaceVersionsError.couldNotCreateFile(at: path)
        }
    }

    mutating func run() throws {
        Internal.initialize()
        let options = try parent.options?.get()
        let forcedVersion = forcedVersion ?? parent.forcedVersion
        var repo = try Internal.openRepo(at: parent.repo)

        let version: Version
        if let forcedVersion {
            version = forcedVersion
        } else if let latest = try repo.latestRelease(
            allowDirty: dryRun,
            untaggedReleaseChannel: parent.channel,
            forceLatestVersionTo: nil,
            options: options
        ), let latestVersion = latest.version {
            version = latestVersion
        } else {
            version = Version(0, 0, 1, build: [Internal.timestamp()])
        }

        try replace(in: &repo, with: version.adding(buildIdentifiers: buildIdentifiers))
    }

    enum Format: String, CaseIterable, ExpressibleByArgument {
        case json = "json"
        case yaml = "yml"
        case plist = "plist"
        case text = "txt"

        init?(fileExtension: String) {
            guard let format = Self(rawValue: fileExtension) else {
                return nil
            }
            self = format
        }

        var fileExtension: String {
            rawValue
        }

        var isStructured: Bool {
            self != .text
        }
    }

    enum Item: String, CaseIterable, ExpressibleByArgument {
        case version
        case shortVersion
        case identifiers
        case prerelease
        case buildInfo
    }
}

enum ReplaceVersionsError: Error, CustomStringConvertible {
    case noSuchFile(at: String)
    case encodingError
    case couldNotCreateFile(at: String)
    case notADictionary(Embed.Format)

    var description: String {
        switch self {
        case .noSuchFile(let path):
            return "No file exists at configured path \(path)."
        case .encodingError:
            return "Encountered data with unexpected encoding format."
        case .couldNotCreateFile(let path):
            return "Could not create file at \(path)."
        case let .notADictionary(format):
            return "The \(format.rawValue)-encoded file is not a dictionary."
        }
    }
}
