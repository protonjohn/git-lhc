//
//  Gittish.swift
//
//  This file defines wrapper types for all of the git objects in the SwiftGit2 library. The extensions of the
//  SwiftGit2 types to conform to these protocols is in the `Dependencies` directory.
//
//  Error types and methods building on top of methods in the SwiftGit2 library also go here.
//
//  Created by John Biggs on 11.10.23.
//

import Foundation
import SwiftGit2
import System

public typealias ObjectID = OID

public protocol Repositoryish {
    var defaultSignature: Signature { get throws }
    var defaultNotesRefName: String { get throws }

    var config: any Configish { get throws }

    func HEAD() throws -> ReferenceType
    mutating func setHEAD(_ oid: ObjectID) throws
    func commit(_ oid: ObjectID) throws -> Commitish
    func commits(in: Branchish) -> CommitishIterator
    func reference(named: String) throws -> ReferenceType
    func localBranch(named: String) throws -> Branchish
    func remoteBranch(named: String) throws -> Branchish
    func tag(named: String) throws -> TagReferenceish
    func tag(_ oid: ObjectID) throws -> Tagish
    func note(for oid: ObjectID, notesRef: String?) throws -> Note
    mutating func notes(notesRef: String?) throws -> LHCNoteIterator

    func object(_ oid: ObjectID) throws -> ObjectType
    func object(parsing: String) throws -> ObjectType

    mutating func createNote(
        for oid: OID,
        message: String,
        author: Signature,
        committer: Signature,
        noteCommitMessage: String?,
        notesRefName: String?,
        force: Bool,
        signingCallback: ((String) throws -> String)?
    ) throws -> Note

    func readNoteCommit(for oid: ObjectID, commit: Commitish) throws -> Note

    mutating func removeNote(
        for oid: ObjectID,
        author: Signature,
        committer: Signature,
        noteCommitMessage: String?,
        notesRefName: String?,
        signingCallback: ((String) throws -> String)?
    ) throws

    mutating func createTag(
        _ name: String,
        target: ObjectType,
        signature: Signature,
        message: String?,
        force: Bool,
        signingCallback: ((String) throws -> String)?
    ) throws -> TagReferenceish

    func allTags() throws -> [TagReferenceish]
    mutating func push(remote remoteName: String, credentials: Credentials, reference: ReferenceType) throws

    mutating func commit(
        tree treeOID: ObjectID,
        parents: [Commitish],
        message: String,
        signature: Signature,
        signingCallback: ((String) throws -> String)?
    ) throws -> Commitish
}

extension Repositoryish {
    public func currentBranch() throws -> Branchish? {
        if let branchName = Internal.branchName,
           let branch = (try? localBranch(named: branchName)) ??
                        (try? remoteBranch(named: branchName)) {
            return branch
        }

        return try? HEAD() as? Branchish
    }

    public func oid(for refName: String) throws -> ObjectID? {
        if let oid = ObjectID(string: refName) { return oid }
        if let tag = try? tag(named: refName) { return tag.oid }
        if let local = try? localBranch(named: refName) { return local.oid }
        if let remote = try? remoteBranch(named: refName) { return remote.oid }

        throw RepositoryError.invalidReference(refName)
    }

    public func commits(since start: ObjectID?) throws -> (branch: Branchish?, commits: [Commitish]) {
        if let branch = try? currentBranch() {
            return try (branch, commits(on: branch, since: start))
        }

        let head = try HEAD()
        return try (head as? Branchish, commits(from: head.oid, since: start))
    }

    public func commits(
        on branch: Branchish,
        since start: ObjectID?,
        where closure: ((Commitish) throws -> Bool)? = nil
    ) throws -> [Commitish] {
        var result: [Commitish] = []
        let branchCommits = commits(in: branch)

        for maybeCommit in branchCommits {
            guard let commit = try? maybeCommit.get() else { break }
            guard try closure?(commit) != false else { continue }
            guard commit.oid != start else { return result }
            result.append(commit)
        }

        guard let start else { return result }
        throw RepositoryError.referenceNotFoundStartingFromLeaf(reference: start, leaf: branch.oid)
    }

    public func commits(from oid: ObjectID, since start: ObjectID?, where closure: ((Commitish) throws -> Bool)? = nil) throws -> [Commitish] {
        var seen = Set<ObjectID>()
        var result: [Commitish] = []
        var frontier = [oid]
        while !frontier.isEmpty {
            if let start {
                guard !frontier.contains(start) else {
                    return result.sorted {
                        $0.date > $1.date
                    }
                }
            }

            let commits: [Commitish] = try frontier
                .compactMap {
                    guard !seen.contains($0) else { return nil }
                    let commit = try self.commit($0)
                    guard try closure?(commit) != false else { return nil }
                    return commit
                }

            result += commits
            frontier.forEach { seen.insert($0) }
            frontier = commits.flatMap { $0.parentOIDs }
        }

        guard let start else { return result }
        throw RepositoryError.referenceNotFoundStartingFromLeaf(reference: start, leaf: oid)
    }

    public func isReachable(_ target: ObjectID, from leaf: ObjectID) throws -> Bool {
        var seen = Set<ObjectID>()
        var frontier = [leaf]
        while !frontier.isEmpty {
            guard !frontier.contains(target) else {
                return true
            }

            let commits: [Commitish] = try frontier
                .compactMap {
                    guard !seen.contains($0) else { return nil }
                    return try self.commit($0)
                }

            frontier.forEach { seen.insert($0) }
            frontier = commits.flatMap { $0.parentOIDs }
        }
        return false
    }

    public func tagsByTarget() throws -> [ObjectID: [TagReferenceish]] {
        return try allTags().reduce(into: [:], { partialResult, tag in
            if partialResult[tag.oid] == nil {
                partialResult[tag.oid] = []
            }
            partialResult[tag.oid]!.append(tag)
        })
    }

    public var defaultNotesRef: ReferenceType {
        get throws {
            let name = try defaultNotesRefName
            return try reference(named: name)
        }
    }

    public func commits(
        on ref: ReferenceType,
        since: ObjectID? = nil,
        where closure: ((Commitish) throws -> Bool)? = nil
    ) throws -> [Commitish] {
        let commit = try commit(ref.oid)
        return try commits(from: ref.oid, since: since, where: closure)
    }

    public func noteCommits(
        on ref: ReferenceType,
        for target: ObjectID,
        since: ObjectID? = nil,
        where closure: ((Commitish, Note) throws -> Bool)? = nil
    ) throws -> [(Commitish, Note)] {
        return try commits(from: ref.oid, since: since)
            .compactMap {
                guard let note = try? readNoteCommit(for: target, commit: $0) else {
                    return nil
                }

                guard try closure?($0, note) != false else {
                    return nil
                }

                return ($0, note)
            }
    }
}

open class MapIterator<Input, Element, Iterator: IteratorProtocol<Input>>: IteratorProtocol, Sequence {
    var wrappedValue: Iterator?

    public typealias Iterator = MapIterator<Input, Element, Iterator>

    let closure: ((Input) -> Element)?

    public init(_ wrappedValue: Iterator?, closure: ((Input) -> Element)?) {
        self.wrappedValue = wrappedValue
        self.closure = closure
    }

    open func next() -> Element? {
        // These use bang-dereferencing, because in the only situation where these would be nil, this
        // function is overridden (i.e., for test mocking).
        guard let next = wrappedValue!.next() else { return nil }
        return closure!(next)
    }
}

public typealias CommitishIterator = MapIterator<Result<Commit, NSError>, Result<Commitish, Error>, CommitIterator>
public typealias LHCNoteIterator = MapIterator<Result<Note, NSError>, Result<Note, Error>, NoteIterator>

enum RepositoryError: Error, CustomStringConvertible {
    case referenceNotFoundStartingFromLeaf(reference: ObjectID, leaf: ObjectID)
    case invalidReference(String)

    var description: String {
        switch self {
        case let .referenceNotFoundStartingFromLeaf(reference, leaf):
            return "Could not reach commit '\(reference)' from commit '\(leaf).'"
        case let .invalidReference(reference):
            return "Invalid reference name '\(reference).' Please specify a tag, branch, or commit hash."
        }
    }
}

public protocol Branchish: ReferenceType {
}

extension Branchish {
    public var name: String {
        shortName ?? longName
    }
}

public protocol TagReferenceish: ReferenceType {
    var message: String? { get }
    var tagOid: ObjectID? { get }
}

extension TagReferenceish {
    public var name: String {
        shortName ?? longName
    }
}

public protocol Tagish: ObjectType, CustomStringConvertible {
    var oid: ObjectID { get }
    var target: Pointer { get }
    var name: String { get }
    var tagger: Signature { get }
    var message: String { get }
}

public protocol Commitish: ObjectType, CustomStringConvertible {
    var parentOIDs: [ObjectID] { get }

    var author: Signature { get }
    var committer: Signature { get }
    var message: String { get }
    var date: Date { get }

    var trailers: [Trailerish] { get throws }
}

extension Commitish {
    public var description: String {
        return """
        commit \(oid.description)
        Author: \(author.description)
        Date:   \(Internal.gitDateString())

        \(message.indented())
        """
    }
}

extension Tagish {
    public var description: String {
        return """
        tag \(name)
        Tagger: \(tagger.description)
        Date:   \(Internal.gitDateString())

        \(message)
        """
    }
}

public protocol Trailerish {
    var key: String { get }
    var value: String { get }
}

public protocol Configish {
    func get(_ type: Bool.Type, _ name: String) -> Result<Bool, NSError>
    func get(_ type: Int32.Type, _ name: String) -> Result<Int32, NSError>
    func get(_ type: Int64.Type, _ name: String) -> Result<Int64, NSError>
    func get(_ type: String.Type, _ name: String) -> Result<String, NSError>
    func get(_ type: FilePath.Type, _ name: String) -> Result<FilePath, NSError>

    mutating func set(_ name: String, value: Bool) -> Result<(), NSError>
    mutating func set(_ name: String, value: Int32) -> Result<(), NSError>
    mutating func set(_ name: String, value: Int64) -> Result<(), NSError>
    mutating func set(_ name: String, value: String) -> Result<(), NSError>

    var global: Self { get throws }
    static var defaultConfig: Self { get throws }
}

public struct SigningOptions {
    public enum Format: String {
        case openpgp
        case x509
        case ssh
    }

    public let format: Format
    public let program: String
    /// - Note: for SSH this can either be a key ID or a file. Extra work needs to be done to support SSH.
    public let keyArg: String

    public var signingCommand: [String] {
        switch format {
        case .openpgp, .x509:
            return [program, "--status-fd=2", "-bsau", keyArg]
        case .ssh:
            fatalError("Signing with SSH keys is not yet supported.")
        }
    }

    public func verifyCommand(fileName: String) -> [String] {
        switch format {
        case .openpgp, .x509:
            return [program, "--status-fd=1", "--verify", fileName, "-"]
        case .ssh:
            fatalError("Verifying SSH signatures is not yet supported.")
        }
    }
}

extension Configish {
    public var signingKey: String? {
        try? get(String.self, "user.signingkey").get()
    }

    public var gpgProgram: String? {
        (try? get(String.self, "gpg.program").get()) ??
            (try? get(String.self, "gpg.openpgp.program").get())
    }

    public var x509Program: String? {
        try? get(String.self, "gpg.x509.program").get()
    }

    public var sshSigningProgram: String? {
        try? get(String.self, "gpg.ssh.program").get()
    }

    public var signingOptions: SigningOptions? {
        guard let signingKey else { return nil }
        if let gpgProgram {
            return .init(format: .openpgp, program: gpgProgram, keyArg: signingKey)
        } else if let x509Program {
            return .init(format: .x509, program: x509Program, keyArg: signingKey)
        } else if let sshSigningProgram {
            return .init(format: .ssh, program: sshSigningProgram, keyArg: signingKey)
        } else {
            return .init(format: .openpgp, program: "gpg", keyArg: signingKey)
        }
    }
}
