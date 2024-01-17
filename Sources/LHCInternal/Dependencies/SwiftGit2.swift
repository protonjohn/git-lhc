//
//  Git.swift
//
//
//  Created by John Biggs on 10.10.23.

import Foundation
import SwiftGit2

extension ObjectType {
    public var commitOid: ObjectID? {
        (self as? Tagish)?.target.oid ?? (self as? Commitish)?.oid
    }
}

extension Repository: Repositoryish {
    public var config: Configish {
        get throws {
            try self.config()
        }
    }

    public var defaultSignature: Signature {
        get throws {
            try self.defaultSignature()
        }
    }

    /// Used for explicitly disambiguating the return value of a function for the compiler.
    private func explicit<T>(_ type: T.Type, _ closure: @autoclosure () throws -> T) rethrows -> T {
        return try closure()
    }

    public func commit(_ oid: ObjectID) throws -> Commitish {
        return try explicit(Commit.self, commit(oid))
    }

    public func localBranch(named name: String) throws -> Branchish {
        return try explicit(Branch.self, localBranch(named: name))
    }

    public func remoteBranch(named name: String) throws -> Branchish {
        return try explicit(Branch.self, remoteBranch(named: name))
    }

    public func tag(named name: String) throws -> TagReferenceish {
        return try explicit(TagReference.self, tag(named: name))
    }

    public func tag(_ oid: ObjectID) throws -> Tagish {
        return try explicit(Tag.self, tag(oid))
    }

    public func createNote(for oid: OID, message: String, author: Signature, committer: Signature, noteCommitMessage: String?, notesRefName: String?, force: Bool, signingCallback: SigningCallback?) throws -> Note {
        return try createNote(for: oid, message: message, author: author, committer: committer, noteCommitMessage: noteCommitMessage, notesRefName: notesRefName, signatureField: nil, force: force, signingCallback: signingCallback)
    }

    public func removeNote(for oid: ObjectID, author: Signature, committer: Signature, noteCommitMessage: String?, notesRefName: String?, signingCallback: SigningCallback?) throws {
        try removeNote(for: oid, author: author, committer: committer, noteCommitMessage: noteCommitMessage, notesRefName: notesRefName, signatureField: nil, signingCallback: signingCallback)
    }

    public func readNoteCommit(for oid: ObjectID, commit: Commitish) throws -> Note {
        return try readNoteCommit(for: oid, commit: commit as! Commit)
    }

    public func createTag(_ name: String, target: ObjectType, signature: Signature, message: String?, force: Bool, signingCallback: SigningCallback?) throws -> Tagish {
        return try explicit(Tag.self, createTag(name, target: target, signature: signature, message: message, force: force, signingCallback: signingCallback))
    }

    public func allTags() throws -> [TagReferenceish] {
        try explicit([TagReference].self, self.allTags())
    }

    public func commit(tree treeOID: ObjectID, parents: [Commitish], message: String, signature: Signature, signingCallback: SigningCallback?) throws -> Commitish {
        try self.commit(
            tree: treeOID,
            parents: parents as! [Commit],
            message: message,
            signature: signature,
            signatureField: nil,
            signingCallback: signingCallback
        )
    }

}

extension Commit: Commitish {
    public var trailers: [Trailer] {
        get throws {
            try trailers().get()
        }
    }

    public var parentOIDs: [ObjectID] {
        parents.map(\.oid)
    }
}

extension Branch: Branchish {
}

extension TagReference: TagReferenceish {
    public var message: String? {
        switch self {
        case .annotated(_, let tag):
            return tag.message
        default:
            return nil
        }
    }

    public var tagOid: ObjectID? {
        switch self {
        case .annotated(_, let tag):
            return tag.oid
        default:
            return nil
        }
    }
}

extension Tag: Tagish {
}

extension TransferProgress {
    public typealias LHCPushNegotiationCallback = (Repositoryish, [Remote.Update]) throws -> ()

    static var transferState: State?
    static var remoteProgress = ""

    static var lastProgressUpdate: Date?
    static var lastThroughputUpdate: Date?

    static var lastBytesReceived: Double?
    static var lastThroughputRate: Double?

    static var lastProgressUpdateString: String?
    static var deferredProgressUpdate: String?

    static var lastPackerStage: PackBuilderStage?
    static var lastDirection: Remote.Direction?
    static var lastRemote: Remote?

    enum MetricFactor: Character, CaseIterable {
        case kilo = "k"
        case mega = "M"
        case giga = "G"
        case tera = "T"

        init?(binaryQuantity: any BinaryFloatingPoint) {
            var index = 0
            var binaryQuantity = Double(binaryQuantity)

            while binaryQuantity > 1024 {
                binaryQuantity /= 1024
                index += 1
            }

            guard let value = Self.allCases[safe: index] else { return nil }
            self = value
        }

        var factorValue: Double {
            // 1024 = 2 ** 10
            Double(1 << (10 * (Self.allCases.firstIndex(of: self)! + 1)))
        }

        var sizeValue: String {
            return "\(rawValue)iB"
        }

        var throughputValue: String {
            return "\(rawValue)iB/s"
        }
    }

    enum State {
        case receivingObjects
        case resolvingDeltas
    }

    func print(force: Bool = false) {
        var done = false

        let now = Date()
        let output: String

        switch Self.transferState {
        case nil:
            Self.transferState = .receivingObjects
            fallthrough
        case .receivingObjects:
            // If indexedDeltas is greater than 0, then we've started resolving deltas.
            guard indexedDeltas == 0 else {
                if let update = Self.deferredProgressUpdate {
                    // Should print with a newline so it doesn't immediately get overwritten by the next print.
                    Internal.print(update)
                }

                Self.transferState = .resolvingDeltas
                fallthrough
            }

            let receivedBytes = Double(receivedBytes)
            let throughput: Double
            if let lastUpdate = Self.lastThroughputUpdate, let lastBytes = Self.lastBytesReceived {
                let timeInterval = now.timeIntervalSince(lastUpdate)
                if timeInterval < .throughputUpdateInterval {
                    throughput = Self.lastThroughputRate ?? 0
                } else {
                    throughput = (receivedBytes - Double(lastBytes)) / timeInterval
                    Self.lastThroughputUpdate = now
                    Self.lastBytesReceived = receivedBytes
                }
            } else {
                throughput = receivedBytes / .throughputUpdateInterval
                Self.lastThroughputUpdate = now
                Self.lastBytesReceived = receivedBytes
            }

            let receivedBytesFactor = MetricFactor(binaryQuantity: receivedBytes)
            let throughputFactor = MetricFactor(binaryQuantity: throughput)

            let receivedBytesMetricValue = receivedBytes / (receivedBytesFactor?.factorValue ?? 1)
            let throughputMetricValue = throughput / (throughputFactor?.factorValue ?? 1)

            let direction = Self.lastDirection == .fetch ? "Receiving" : "Sending"
            done = receivedObjects == totalObjects
            output = String(
                format: "\(direction) objects: %3d%% (%d/%d), %.2f %s | %.2f %s%s",
                Int.percent(receivedObjects, totalObjects),
                receivedObjects,
                totalObjects,
                receivedBytesMetricValue,
                receivedBytesFactor?.sizeValue ?? "B",
                throughputMetricValue,
                throughputFactor?.throughputValue ?? "B/s",
                done ? ", done." : ""
            )
        case .resolvingDeltas:
            done = indexedDeltas == totalDeltas
            output = String(
                format: "Resolving deltas: %3d%% (%d/%d)%s",
                Int.percent(indexedDeltas, totalDeltas),
                indexedDeltas,
                totalDeltas,
                done ? ", done." : ""
            )
        }

        if done {
            Self.lastBytesReceived = nil
            Self.lastProgressUpdate = nil
            Self.lastThroughputRate = nil
            Self.lastThroughputUpdate = nil
            Self.lastProgressUpdateString = nil
            Self.deferredProgressUpdate = nil
        }

        Self.printProgress(output, now: now, done: done, force: force)
    }

    static func printProgress(_ string: String, now: Date = .now, done: Bool, force: Bool = false) {
        if !(force || done), let last = Self.lastProgressUpdate, now.timeIntervalSince(last) < .progressUpdateInterval {
            Self.deferredProgressUpdate = string
        } else {
            Self.deferredProgressUpdate = nil
            let lastLength = Self.lastProgressUpdateString?.count ?? 0
            let diff = lastLength - string.count
            let padding = String(repeating: " ", count: 1 + ((diff < 0) ? 0 : diff)) // add one to replace newline?

            Self.lastProgressUpdate = now
            Self.lastProgressUpdateString = string
            Internal.print(string + padding, terminator: done ? "\n" : "\r")
        }
    }

    static var remoteProgressCallback: RemoteProgressCallback = {
        Self.remoteProgress += $0
        var lines = remoteProgress.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)

        let last = lines.removeLast()
        for line in lines {
            Internal.print("remote: \(line)\n")
        }

        remoteProgress = String(last)
    }

    static var packerCallback: PackerProgressCallback = { stage, current, total in
        // stage is "counting" vs "compressing"
        let done = current == total
        let output: String
        switch stage {
        case .addingObjects:
            output = String(format: "Counting objects: %d", current)
        case .deltafication:
            if Self.lastPackerStage == .addingObjects {
                Internal.print("") // Add a newline
            }

            let percent = Int.percent(current, total)
            output = String(format: "Compressing objects: %3d%% (%d/%d)", percent, current, total)
        }

        Self.lastPackerStage = done ? nil : stage
        Self.printProgress(output, done: done)
    }

    static var transferProgressCallback: TransferProgressCallback = { progress in
        progress.print()
    }

    static var remoteReadyCallback: RemoteReadyCallback = { remote, direction in
        Self.lastRemote = remote
        Self.lastDirection = direction
    }

    static var pushNegotiationCallback: LHCPushNegotiationCallback = { repo, updates in
        guard let remote = Self.lastRemote else {
            throw GitError(
                code: .invalid,
                detail: .net,
                description: "remoteReadyCallback hasn't been called yet?"
            )
        }

        var updateStrings: [String] = []
        for update in updates {
            var oids: Set<ObjectID> = []
            for commit in (try? repo.commits(from: update.newTarget, since: nil)) ?? [] {
                oids.insert(commit.oid)
            }
            for commit in (try? repo.commits(from: update.currentTarget, since: nil)) ?? [] {
                oids.insert(commit.oid)
            }
            let length = (try? ObjectID.minimumLength(toLosslesslyRepresent: oids)) ?? ObjectID.stringLength

            let current = update.currentTarget.description.dropFirst(length)
            let new = update.newTarget.description.dropFirst(length)
            updateStrings.append(" + \(current)...\(new) \(update.source) -> \(update.destination)")
        }

        Internal.print("""
            To \(remote.URL)
            \(updateStrings.joined(separator: "\n"))
            """)
    }
}

extension PushOptions {
    static func cliOptions(repo: Repositoryish) throws -> PushOptions {
        let options = try PushOptions()
        options.packerCallback = TransferProgress.packerCallback
        options.remoteProgressCallback = TransferProgress.remoteProgressCallback
        options.transferProgressCallback = TransferProgress.transferProgressCallback
        options.remoteReadyCallback = TransferProgress.remoteReadyCallback
        options.pushNegotiationCallback = { updates in
            try TransferProgress.pushNegotiationCallback(repo, updates)
        }
        return options
    }
}

extension FetchOptions {
    static func cliOptions(repo: Repositoryish) throws -> FetchOptions {
        let options = try FetchOptions()
        options.packerCallback = TransferProgress.packerCallback
        options.remoteProgressCallback = TransferProgress.remoteProgressCallback
        options.transferProgressCallback = TransferProgress.transferProgressCallback
        options.remoteReadyCallback = TransferProgress.remoteReadyCallback
        options.pushNegotiationCallback = { updates in
            try TransferProgress.pushNegotiationCallback(repo, updates)
        }
        return options
    }
}

fileprivate extension TimeInterval {
    static let progressUpdateInterval: Self = .milliseconds(60)
    static let throughputUpdateInterval: Self = .milliseconds(500)
}

extension Internal {
    public static internal(set) var openRepo: ((URL) -> Result<Repositoryish, Error>) = {
        do {
            return try .success(Repository.at($0) as Repositoryish)
        } catch {
            return .failure(error)
        }
    }

    public static func openRepo(at path: String) throws -> Repositoryish {
        let url = URL(filePath: path, directoryHint: .isDirectory)
        return try Self.openRepo(url).get()
    }

    public static var defaultGitConfig: (any Configish)? = (try? Config.default())
}

extension Config: Configish {
}
