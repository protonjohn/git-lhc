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

struct ReplaceVersions: ParsableCommand {
    typealias Format = Configuration.VersionReplacementFormat

    static let configuration = CommandConfiguration(
        abstract: "Modify the version files for the configured train according to the current version."
    )

    @OptionGroup()
    var parent: Gluon.Options

    @Option(
        name: .shortAndLong,
        help: "Which trains to replace versions for.",
        transform: Configuration.train(named:)
    )
    var train: Configuration.Train? = .environment

    @Argument(transform: { (versionString: String) throws -> Version in
        guard let version = Version(versionString) else {
            throw CreateReleaseError.invalidVersion(versionString)
        }

        return version
    })
    var forcedVersion: Version? = .environment

    func validate() throws {
        guard let train else {
            throw ValidationError("Must specify a train with --train.")
        }

        guard let replace = train.replace, !replace.isEmpty else {
            throw ValidationError("No version replacements are configured for train '\(train.name)'.")
        }
    }

    func decode(contents: Data, format: Format) throws -> [String: CodableCollection] {
        let collection: CodableCollection
        switch format {
        case .json:
            collection = try JSONDecoder()
                .decode(CodableCollection.self, from: contents)
        case .yaml:
            collection = try YAMLDecoder()
                .decode(CodableCollection.self, from: contents)
        case .plist:
            collection = try PropertyListDecoder()
                .decode(CodableCollection.self, from: contents)
        default:
            fatalError("Unsupported format \(format)")
        }

        guard case .dictionary(let dictionary) = collection else {
            throw ReplaceVersionsError.notADictionary(format)
        }

        return dictionary
    }

    func encode(dictionary: [String: CodableCollection], format: Format) throws -> Data? {
        let result: StringOrData
        switch format {
        case .json:
            result = try .init(JSONEncoder().encode(dictionary))
        case .yaml:
            result = try .init(YAMLEncoder().encode(dictionary))
        case .plist:
            result = try .init(PropertyListEncoder().encode(dictionary))
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
        dictionary[key] = .string(value)
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

    func replace(in repo: inout Repositoryish, with version: Version) throws {
        let replacements = train!.replace!
        let baseURL = URL(string: parent.repo)!

        for replacement in replacements {
            let path = baseURL
                .appending(component: replacement.file, directoryHint: .notDirectory)
                .path()

            let item = replacement.item ?? .fullVersion
            let value: String
            switch item {
            case .fullVersion:
                value = version.description
            case .version:
                value = "\(version.major).\(version.minor).\(version.patch)"
            case .identifiers:
                var result = version.prereleaseIdentifiers.joined(separator: ".")
                if !result.isEmpty {
                    let build = version.buildMetadataIdentifiers.joined(separator: ".")
                    result += "+\(build)"
                }
                value = result
            case .prereleaseIdentifiers:
                value = version.prereleaseIdentifiers.joined(separator: ".")
            case .buildIdentifiers:
                value = version.buildMetadataIdentifiers.joined(separator: ".")
            }

            guard var contents = Gluon.fileManager.contents(atPath: path) else {
                throw ReplaceVersionsError.noSuchFile(at: path)
            }

            let format = replacement.format ?? .plaintext
            if format.isStructured {
                try replaceStructured(
                    contents: &contents,
                    key: replacement.key,
                    value: value,
                    format: format
                )
            } else {
                try replaceText(
                    contents: &contents,
                    replace: replacement.key,
                    with: value
                )
            }

            try Gluon.fileManager.removeItem(atPath: path)
            guard Gluon.fileManager.createFile(atPath: path, contents: contents) else {
                throw ReplaceVersionsError.couldNotCreateFile(at: path)
            }
        }
    }

    func run() throws {
        SwiftGit2.initialize()
        var repo = try Gluon.openRepo(at: parent.repo)

        let version: Version
        if let forcedVersion {
            version = forcedVersion
        } else if let latest = try repo.latestRelease(
            for: train,
            allowDirty: false,
            untaggedPrereleaseChannel: nil,
            forceLatestVersionTo: nil
        ), let latestVersion = latest.version {
            version = latestVersion
        } else {
            version = Version(0, 0, 1, build: [Gluon.timestamp()])
        }

        try replace(in: &repo, with: version)
    }
}

enum ReplaceVersionsError: Error, CustomStringConvertible {
    case noSuchFile(at: String)
    case encodingError
    case couldNotCreateFile(at: String)
    case notADictionary(Configuration.VersionReplacementFormat)

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
