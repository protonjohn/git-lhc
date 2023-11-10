//
//  CreateRelease.swift
//  
//
//  Created by John Biggs on 13.10.23.
//

import Foundation
import SwiftGit2
import ArgumentParser
import Version

struct CreateRelease: AsyncParsableCommand, QuietCommand {
    static let configuration = CommandConfiguration(
        abstract: "Tag a release at HEAD, deriving a version according to the passed options if no version is specified."
    )

    @OptionGroup()
    var parent: Gluon.Options

    @Option(
        name: .shortAndLong,
        help: "The release train to use, if any are configured in the project.",
        transform: Configuration.train(named:)
    )
    var train: Configuration.Train? = .environment

    @Option(
        name: .shortAndLong,
        help: "Which release channel to tag for. Possible values are \(ReleaseChannel.possibleValues)."
    )
    var channel: ReleaseChannel = .production

    @Option(
        name: .shortAndLong,
        parsing: .upToNextOption,
        help: "Additional prerelease identifiers to add to the version tag."
    )
    var prereleaseIdentifiers: [String] = []

    @Option(
        name: .shortAndLong,
        parsing: .upToNextOption,
        help: "Additional build metadata identifiers to add to the version tag."
    )
    var buildIdentifiers: [String] = []

    @Option(
        name: .shortAndLong,
        help: "The ssh identity to use when pushing."
    )
    var identity: String = {
        let home = Gluon.fileManager.homeDirectoryForCurrentUser
            .appending(path: ".ssh", directoryHint: .isDirectory)
            .appending(path: "id_rsa", directoryHint: .notDirectory)
        return home.path()
    }()

    @Flag(
        name: .shortAndLong,
        help: "Quiet (non-interactive). Don't prompt for passwords or confirmation."
    )
    var quiet: Bool = false

    @Flag(
        name: .customLong("timestamp"),
        help: "Add the current timestamp as a build identifier to the version tag."
    )
    var buildTimestamp: Bool = false

    @Flag(help: "Push the resulting tag to the specified remote (see the '--remote' option.)")
    var push: Bool = false

    @Option(help: "The remote to use when pushing the tag.")
    var remote: String = "origin"

    @Flag(
        inversion: .prefixedNo,
        help: GluonEnvironment.jiraEndpoint.value == nil ? .hidden : """
            Don't attempt to communicate with JIRA. If you find yourself doing this often, consider \
            unsetting \(GluonEnvironment.jiraEndpoint.rawValue).
            """
    )
    var jira: Bool = true

    @Argument(transform: { (versionString: String) throws -> Version in
        guard let version = Version(versionString) else {
            throw CreateReleaseError.invalidVersion(versionString)
        }

        return version
    })
    var forcedVersion: Version? = .environment

    func validate() throws {
        guard !prereleaseIdentifiers.contains(channel.rawValue) else {
            throw CreateReleaseError.optionAlreadySpecifies(channel)
        }

        if let forcedVersion {
            for prereleaseIdentifier in prereleaseIdentifiers {
                guard !forcedVersion.prereleaseIdentifiers.contains(prereleaseIdentifier) else {
                    throw CreateReleaseError.versionAlreadyContains(version: forcedVersion, identifier: prereleaseIdentifier)
                }
            }

            for buildIdentifier in buildIdentifiers {
                guard !forcedVersion.buildMetadataIdentifiers.contains(buildIdentifier) else {
                    throw CreateReleaseError.versionAlreadyContains(version: forcedVersion, identifier: buildIdentifier)
                }
            }
        }
    }

    func push(repo: inout Repositoryish, tag: TagReferenceish) throws {
        let privateKeyPath = identity
        let publicKeyPath = URL(filePath: privateKeyPath, directoryHint: .notDirectory)
            .appendingPathExtension("pub")
            .path()

        let passphrase = readPassphraseIfNotQuiet() ?? ""

        try repo.push(
            remote: remote,
            credentials: .sshPath(
                publicKeyPath: publicKeyPath,
                privateKeyPath: privateKeyPath,
                passphrase: passphrase
            ),
            reference: tag
        )
    }

    func createTag(in repo: inout Repositoryish, for release: Release) throws {
        let tagName = (train?.tagPrefix ?? "") + release.versionString
        let branch = try repo.currentBranch() ?? repo.HEAD()
        let signature = try repo.defaultSignature

        // Get the commit object for the given OID
        let commit = try repo.commit(branch.oid)

        var message = "release: "
        if let train {
            message += "\(train.displayName ?? train.name) "
        }
        message += release.versionString

        if let body = release.body {
            message += "\n\n\(body)"
        }

        guard promptForConfirmationIfNotQuiet("""
            Will create tag:
            tag \(tagName)
            Tagger: \(signature)
            Date: [...]

            \(message)

            Continue?
            """, continueText: false) else {
            throw CreateReleaseError.userAborted
        }

        let tag = try repo.createTag(
            tagName,
            target: commit,
            signature: signature,
            message: message
        )

        if push {
            guard promptForConfirmationIfNotQuiet("Will push tag \(tagName) to \(remote).") else {
                throw CreateReleaseError.userAborted
            }

            try push(repo: &repo, tag: tag)
        }
    }

    func editNotes(for release: Release) async throws -> String? {
        guard jira,
           let fieldName = Configuration.configuration.jiraReleaseNotesField,
           let jiraClient = Gluon.jiraClient,
            case let projectIds = release.changes.values.flatMap({ $0.flatMap(\.projectIds) }),
              !projectIds.isEmpty else {
            return nil
        }

        let issues = try await jiraClient.issues(ids: projectIds)
        var releaseNotes = issues.compactMap {
            $0.fields.fieldByName(fieldName) as? String
        }.map {
            "- \($0)"
        }.joined(separator: "\n")

        if !quiet {
            Gluon.print("Release notes:", releaseNotes, separator: "\n")
            if Gluon.promptForConfirmation("Edit?", continueText: false, defaultAction: false) {
                releaseNotes = try Gluon.fileManager.editFile(
                    releaseNotes,
                    temporaryFileName: "release_notes.txt"
                ) ?? ""
            }
        }
        return releaseNotes
    }

    mutating func run() async throws {
        SwiftGit2.initialize()

        let prereleaseChannel = channel.isPrerelease ? channel : nil

        if buildTimestamp {
            buildIdentifiers.insert(Gluon.timestamp(), at: 0)
        }

        var repo = try Gluon.openRepo(at: parent.repo)
        guard var release = try repo.latestRelease(
            for: train,
            allowDirty: true,
            untaggedPrereleaseChannel: prereleaseChannel?.rawValue,
            forceLatestVersionTo: forcedVersion
        )?.adding(
            prereleaseIdentifiers: prereleaseIdentifiers,
            buildIdentifiers: buildIdentifiers
        ) else {
            fatalError("Invariant error: no release found or created")
        }

        if let notes = try await editNotes(for: release) {
            release = release.adding(notes: notes)
        }

        try createTag(in: &repo, for: release)
    }
}

enum CreateReleaseError: Error, CustomStringConvertible {
    case userAborted
    case invalidVersion(String)
    case requiresCreatingTag
    case cantReplaceVersionsWithoutTrain
    case optionAlreadySpecifies(ReleaseChannel)
    case versionAlreadyContains(version: Version, identifier: String)

    var description: String {
        switch self {
        case .userAborted:
            return "User aborted."
        case .requiresCreatingTag:
            return "Cannot be specified with --no-tag."
        case .cantReplaceVersionsWithoutTrain:
            return "Can't replace versions in files without first specifying a train."
        case .invalidVersion(let invalidVersion):
            return "Invalid version \"\(invalidVersion)\"."
        case .optionAlreadySpecifies(let channel):
            return "--\(channel) was already specified, did you mean to also include it in --prerelease-identifiers?"
        case let .versionAlreadyContains(version, identifier):
            return "The specified version \"\(version)\" already contains the identifier \"\(identifier)\"."
        }
    }
}
