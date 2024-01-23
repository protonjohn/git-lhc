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

fileprivate var tagsByTargetCached: [ObjectID: [TagReferenceish]]?

public protocol Repositoryish {
    var defaultNotesRefName: String { get throws }

    var config: any Configish { get throws }
    var defaultSignature: Signature { get throws }

    func HEAD() throws -> ReferenceType
    mutating func setHEAD(_ oid: ObjectID) throws
    func commit(_ oid: ObjectID) throws -> Commitish
    func reference(named: String) throws -> ReferenceType
    func references(withPrefix prefix: String) throws -> [ReferenceType]

    func localBranch(named: String) throws -> Branchish
    func remoteBranch(named: String) throws -> Branchish
    func tag(named: String) throws -> TagReferenceish
    func tag(_ oid: ObjectID) throws -> Tagish
    func note(for oid: ObjectID, notesRef: String?) throws -> Note

    func object(_ oid: ObjectID) throws -> ObjectType
    func object(parsing: String) throws -> ObjectType
    func blob(_ oid: ObjectID) throws -> Blob

    mutating func createNote(
        for oid: OID,
        message: String,
        author: Signature,
        committer: Signature,
        noteCommitMessage: String?,
        notesRefName: String?,
        force: Bool,
        signingCallback: Repository.SigningCallback?
    ) throws -> Note

    func readNoteCommit(for oid: ObjectID, commit: Commitish) throws -> Note

    mutating func removeNote(
        for oid: ObjectID,
        author: Signature,
        committer: Signature,
        noteCommitMessage: String?,
        notesRefName: String?,
        signingCallback: Repository.SigningCallback?
    ) throws

    mutating func createTag(
        _ name: String,
        target: ObjectType,
        signature: Signature,
        message: String?,
        force: Bool,
        signingCallback: Repository.SigningCallback?
    ) throws -> Tagish

    func allTags() throws -> [TagReferenceish]
    mutating func push(remote remoteName: String, options: PushOptions, reference: ReferenceType) throws

    mutating func commit(
        tree treeOID: ObjectID,
        parents: [Commitish],
        message: String,
        signature: Signature,
        signingCallback: Repository.SigningCallback?
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
        let branch = try? currentBranch()
        let head = try branch ?? HEAD()

        return try (head as? Branchish, commits(from: head.oid, since: start))
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

    /// - Important: the result of this function is cached. Make sure to update the dictionary if modifying any tags.
    public func tagsByTarget() throws -> [ObjectID: [TagReferenceish]] {
        if let tagsByTargetCached {
            return tagsByTargetCached
        }

        tagsByTargetCached = try allTags().reduce(into: [:], { partialResult, tag in
            if partialResult[tag.oid] == nil {
                partialResult[tag.oid] = []
            }
            partialResult[tag.oid as ObjectID]!.append(tag)
        })
        return tagsByTargetCached!
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
        return try commits(from: ref.oid, since: since, where: closure)
    }

    /// Read the note commits on a given reference, like `refs/notes/commits`, that match the given closure.
    public func noteCommits(
        on ref: ReferenceType,
        for target: ObjectID,
        since: ObjectID? = nil,
        where closure: ((Commitish, Note?) throws -> Bool)? = nil
    ) throws -> [(Commitish, Note?)] {
        return try commits(from: ref.oid, since: since)
            .compactMap {
                let note = try? readNoteCommit(for: target, commit: $0)
                guard try closure?($0, note) != false else {
                    return nil
                }

                return ($0, note)
            }
    }

    /// Find the most recent commit (or tag) in a given history that has a note in the given notes reference.
    public func lastNotedObject(
        from: ObjectID,
        since: ObjectID? = nil,
        notesRef: String
    ) throws -> (ObjectType, Note)? {
        let tagsByOid = try tagsByTarget()
        var frontier: Set<ObjectID> = [from]
        var seen: Set<ObjectID> = []
        while !frontier.isEmpty {
            if let since {
                guard !frontier.contains(since) else {
                    return nil
                }
            }

            for oid in frontier {
                guard !seen.contains(oid) else { continue }
                guard let note = try? note(for: oid, notesRef: notesRef) else { continue }

                return try (self.commit(oid), note)
            }

            seen.formUnion(frontier)

            let tagOids = frontier.flatMap({ tagsByOid[$0] ?? [] }).compactMap(\.tagOid)
            for tagOid in tagOids {
                guard !seen.contains(tagOid),
                   let note = try? note(for: tagOid, notesRef: notesRef) else {
                    continue
                }
                return try (self.tag(tagOid), note)
            }

            seen.formUnion(tagOids)

            frontier = frontier.reduce(into: Set<ObjectID>()) {
                let parentOids = try? commit($1).parentOIDs
                $0.formUnion(parentOids ?? [])
            }.subtracting(seen)
        }

        return nil
    }

    /// Similar to ``lastNotedObject(from:since:notesRef:)``, except it returns an array of commits and tags.
    public func notedObjects(
        from: ObjectID,
        since: ObjectID? = nil,
        notesRef: String
    ) throws -> [(ObjectType, Note)] {
        var result: [(ObjectType, Note)] = []

        let tagsByOid = try tagsByTarget()
        var frontier: Set<ObjectID> = [from]
        var seen: Set<ObjectID> = []
        while !frontier.isEmpty {
            if let since {
                guard !frontier.contains(since) else {
                    break
                }
            }

            for oid in frontier {
                guard !seen.contains(oid) else { continue }
                guard let note = try? note(for: oid, notesRef: notesRef) else { continue }

                try result.append((self.commit(oid), note))
            }

            seen.formUnion(frontier)

            let tagOids = frontier.flatMap({ tagsByOid[$0] ?? [] }).compactMap(\.tagOid)
            for tagOid in tagOids {
                guard !seen.contains(tagOid),
                   let note = try? note(for: tagOid, notesRef: notesRef) else {
                    continue
                }
                try result.append((self.tag(tagOid), note))
            }

            seen.formUnion(tagOids)

            frontier = frontier.reduce(into: Set<ObjectID>()) {
                let parentOids = try? commit($1).parentOIDs
                $0.formUnion(parentOids ?? [])
            }.subtracting(seen)
        }

        return result
    }


    /// - Warning: if the repository root is something other than `Internal.repoPath`, it's necessary to specify it.
    public func aliasMap(repositoryRoot: String = Internal.repoPath) throws -> AliasMap {
        let mailmap: String

        if let blobOidString = try config.mailmapBlob,
                  let oid = ObjectID(string: blobOidString),
                  let blob = try? blob(oid),
                  let contents = String(data: blob.data, encoding: .utf8) {
            mailmap = contents
        } else {
            let fileName = try config.mailmapFile ?? ".mailmap"
            let mailmapPath = URL(filePath: repositoryRoot)
                .appending(path: fileName)
                .absoluteURL
                .path(percentEncoded: false)

            guard let data = Internal.fileManager.contents(atPath: mailmapPath),
                  let contents = String(data: data, encoding: .utf8) else {
                throw POSIXError(.ENOENT)
            }

            mailmap = contents
        }

        return try AliasMap(contents: mailmap)
    }

    public mutating func push(remote: String, reference: ReferenceType) throws {
        try push(remote: remote, options: PushOptions.cliOptions(repo: self), reference: reference)
    }
}

/// Similar to a mailmap, except we hold onto the contents to take advantage of extra functionality for looking up
/// things like slack and gitlab usernames.
///
/// Extra usernames appear in the mailmap as `<username@platform>`, for example, an entry for Jane Doe's Gitlab account
/// might look something like:
/// ```
/// Jane Doe <jdoe@example.org> jdoe <jdoe@gitlab>
/// ```
public final class AliasMap: Mailmap {
    let contents: String

    public init(contents: String) throws {
        self.contents = contents

        try super.init(parsing: contents)
    }

    public func alias(username: String, platform: String) throws -> (name: String, email: String) {
        try resolve(name: "", email: "\(username)@\(platform)")
    }

    public func alias(name: String, email: String, platform: String) throws -> String {
        // First, let's normalize the input name.
        let (name, email) = try resolve(name: name, email: email)

        guard let line = contents.split(separator: "\n").first(where: {
            $0.hasPrefix("\(name) <\(email)>") &&
            $0.hasSuffix("@\(platform)>")
        }) else {
            throw POSIXError(.ENOENT)
        }

        // Our line looks like:
        // Jane Doe <jdoe@example.org> <jdozer@slack>
        // Split on the ">" in the middle of the string to get the second component, which just contains the alias.
        let components = line.split(separator: "> ", maxSplits: 1)
        guard components.count == 2 else {
            throw POSIXError(.EINVAL)
        }

        // components[1] should look like:
        // <jdozer@slack>
        // Split the string on "@" and trim any characters to get the username.
        var alias = components[1].trimmingCharacters(in: .whitespaces)
        guard alias.hasPrefix("<") && alias.hasSuffix(">") else {
            throw POSIXError(.EINVAL)
        }

        alias.removeFirst()
        return String(alias.split(separator: "@").first!)
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


enum RepositoryError: Error, CustomStringConvertible {
    case referenceNotFoundStartingFromLeaf(reference: ObjectID, leaf: ObjectID)
    case invalidReference(String)

    var description: String {
        switch self {
        case let .referenceNotFoundStartingFromLeaf(reference, leaf):
            return "Could not reach commit '\(reference)' from commit '\(leaf).'"
        case let .invalidReference(reference):
            return "Invalid reference name '\(reference)'. Please specify a tag, branch, or commit hash."
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

    var trailers: [Commit.Trailer] { get throws }
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

public protocol Configish {
    func get(_ type: Bool.Type, _ name: String) throws -> Bool
    func get(_ type: Int32.Type, _ name: String) throws -> Int32
    func get(_ type: Int64.Type, _ name: String) throws -> Int64
    func get(_ type: String.Type, _ name: String) throws -> String
    func get(_ type: FilePath.Type, _ name: String) throws -> FilePath

    mutating func set(_ name: String, value: Bool) throws
    mutating func set(_ name: String, value: Int32) throws
    mutating func set(_ name: String, value: Int64) throws
    mutating func set(_ name: String, value: String) throws

    var global: Self { get throws }
    static func `default`() throws -> Self
}

public struct SigningOptions {
    public static let statusDescriptor: Int32 = 3
    public static let inputDescriptor: Int32 = 4
    public static let outputDescriptor: Int32 = 5

    internal static let ioDescription = "--status-fd=\(statusDescriptor) <&\(inputDescriptor) >&\(outputDescriptor)"

    public enum Format: String {
        case openpgp
        case x509
        case ssh
    }

    public let format: Format
    public let program: String
    /// - Note: for SSH this can either be a key ID or a file. Extra work needs to be done to support SSH.
    public let keyArg: String

    public var signingCommand: String {
        switch format {
        case .openpgp, .x509:
            return "\(program) -bsau \(keyArg) \(Self.ioDescription)"
        case .ssh:
            fatalError("Signing with SSH keys is not yet supported.")
        }
    }

    public func verifyCommand(fileName: String) -> String {
        switch format {
        case .openpgp, .x509:
            return "\(program) --verify \(fileName) \(Self.ioDescription)"
        case .ssh:
            fatalError("Verifying SSH signatures is not yet supported.")
        }
    }
}

extension Configish {
    public subscript(_ key: String) -> String? {
        try? get(String.self, key)
    }

    public var signingKey: String? {
        self["user.signingkey"]
    }

    public var gpgProgram: String? {
        self["gpg.program"] ?? self["gpg.openpgp.program"]
    }

    public var x509Program: String? {
        self["gpg.x509.program"]
    }

    public var sshSigningProgram: String? {
        self["gpg.ssh.program"]
    }

    public var mailmapFile: String? {
        self["mailmap.file"]
    }

    public var mailmapBlob: String? {
        self["mailmap.blob"]
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
