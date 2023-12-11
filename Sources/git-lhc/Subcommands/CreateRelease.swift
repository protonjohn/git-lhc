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
import LHC
import LHCInternal

struct CreateRelease: AsyncParsableCommand, QuietCommand {
    static let configuration = CommandConfiguration(
        commandName: "release",
        abstract: "Tag a release at HEAD, deriving a version according to the passed options if no version is specified."
    )

    @OptionGroup()
    var parent: LHC.Options

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
        let home = Internal.fileManager.homeDirectoryForCurrentUser
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
        help: LHCEnvironment.jiraEndpoint.value == nil ? .hidden : """
            Don't attempt to communicate with JIRA. If you find yourself doing this often, consider \
            unsetting \(LHCEnvironment.jiraEndpoint.rawValue).
            """
    )
    var jira: Bool = true

    @Argument(
        transform: { (versionString: String) throws -> Version in
            guard let version = Version(versionString) else {
                throw CreateReleaseError.invalidVersion(versionString)
            }

            return version
        }
    )
    var forcedVersion: Version? = nil

    mutating func validate() throws {
        let forcedVersion = forcedVersion ?? parent.forcedVersion

        guard !prereleaseIdentifiers.contains(parent.channel.rawValue) else {
            throw CreateReleaseError.optionAlreadySpecifies(parent.channel)
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

    mutating func createTag(in repo: inout Repositoryish, for release: Release, options: Configuration.Options?) throws {
        let tagName = (options?.tagPrefix ?? "") + release.versionString
        let branch = try repo.currentBranch() ?? repo.HEAD()
        let signature = try repo.defaultSignature

        // Get the commit object for the given OID
        let commit = try repo.commit(branch.oid)

        var message = "release: "
        if let train = options?.train {
            message += "\(options?.trainDisplayName ?? train) "
        }
        message += release.versionString

        if let body = release.body {
            message += "\n\n\(body)"
        }

        let signingKey = try? parent.gitConfig?.get().signingKey
        let dateFormatter = DateFormatter()
        // Sun Nov 12 16:20:42 2023 +0100
        dateFormatter.dateFormat = "EEE MMM d HH:MM:SS YYYY Z"
        guard promptForConfirmationIfNotQuiet("""
            Will create \(signingKey != nil ? "and sign " : "")tag:
            tag \(tagName)
            Tagger: \(signature)
            Date: ~\(dateFormatter.string(from: Date()))

            \(message)

            Continue?
            """, continueText: false) else {
            throw CreateReleaseError.userAborted
        }

        var signingCallback: ((String) throws -> String)?
        if let signingOptions = try parent.signingOptions() {
            signingCallback = {
                try LHC.sign($0, options: signingOptions)
            }
        }

        let tag = try repo.createTag(
            tagName,
            target: commit,
            signature: signature,
            message: message,
            force: false,
            signingCallback: signingCallback
        )

        if push {
            guard promptForConfirmationIfNotQuiet("Will push tag \(tagName) to \(remote).") else {
                throw CreateReleaseError.userAborted
            }

            try push(repo: &repo, tag: tag)
        }
    }

    mutating func editNotes(for release: Release, options: Configuration.Options?) async throws -> String? {
        guard jira,
           let fieldName = options?.jiraReleaseNotesField,
           let jiraClient = Internal.jiraClient,
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
            Internal.print("Release notes:", releaseNotes, separator: "\n")
            if Internal.promptForConfirmation("Edit?", continueText: false, defaultAction: false) {
                releaseNotes = try Internal.fileManager.editFile(
                    releaseNotes,
                    temporaryFileName: "release_notes.txt"
                ) ?? ""
            }
        }
        return releaseNotes
    }

    mutating func run() async throws {
        Internal.initialize()
        let options = try parent.options?.get()
        let forcedVersion = forcedVersion ?? parent.forcedVersion

        if buildTimestamp {
            buildIdentifiers.insert(Internal.timestamp(), at: 0)
        }

        var repo = try Internal.openRepo(at: parent.repo)
        guard var release = try repo.latestRelease(
            allowDirty: true,
            untaggedReleaseChannel: parent.channel,
            forceLatestVersionTo: forcedVersion,
            options: options
        )?.adding(
            prereleaseIdentifiers: prereleaseIdentifiers,
            buildIdentifiers: buildIdentifiers
        ) else {
            fatalError("Invariant error: no release found or created")
        }

        if let notes = try await editNotes(for: release, options: options) {
            release = release.adding(notes: notes)
        }

        try createTag(in: &repo, for: release, options: options)
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
