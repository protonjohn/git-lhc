//
//  Git.swift
//
//
//  Created by John Biggs on 10.10.23.

import Foundation
import SwiftGit2

extension Repository: Repositoryish {
    public var defaultSignature: Signature {
        get throws {
            return try defaultSignature().get()
        }
    }

    public var config: any Configish {
        get throws {
            return try config().get()
        }
    }

    public func HEAD() throws -> ReferenceType {
        return try HEAD().get()
    }

    public func setHEAD(_ oid: ObjectID) throws {
        try setHEAD(oid).get()
    }

    public func commit(_ oid: ObjectID) throws -> Commitish {
        return try commit(oid).get()
    }

    public func commits(in branch: Branchish) -> CommitishIterator {
        return CommitishIterator(commits(in: branch as! Branch)) {
            $0.map { $0 }.mapError { $0 }
        }
    }

    public func localBranch(named name: String) throws -> Branchish {
        return try localBranch(named: name).get()
    }

    public func remoteBranch(named name: String) throws -> Branchish {
        return try remoteBranch(named: name).get()
    }

    public func tag(named name: String) throws -> TagReferenceish {
        return try tag(named: name).get()
    }

    public func tag(_ oid: ObjectID) throws -> Tagish {
        return try tag(oid).get()
    }

    public func createNote(
        for oid: ObjectID,
        message: String,
        author: Signature,
        committer: Signature,
        noteCommitMessage: String?,
        notesRefName: String?,
        force: Bool,
        signingCallback: ((String) throws -> String)?
    ) throws -> Note {
        return try createNote(
            for: oid,
            message: message,
            author: author,
            committer: committer,
            noteCommitMessage: noteCommitMessage,
            notesRefName: notesRefName,
            force: force,
            signingCallback: signingCallback
        ).get()
    }

    public func note(for oid: ObjectID, notesRef: String?) throws -> Note {
        return try note(for: oid, notesRef: notesRef).get()
    }

    public func notes(notesRef: String?) throws -> LHCNoteIterator {
        return try LHCNoteIterator(NoteIterator(repo: self, notesRef: notesRef), closure: {
            $0.map { $0 }.mapError { $0 }
        })
    }

    public func readNoteCommit(for oid: ObjectID, commit: Commitish) throws -> Note {
        return try readNoteCommit(for: oid, commit: commit as! Commit).get()
    }

    public func removeNote(
        for oid: ObjectID,
        author: Signature,
        committer: Signature,
        noteCommitMessage: String?,
        notesRefName: String?,
        signingCallback: ((String) throws -> String)?
    ) throws {
        return try removeNote(
            for: oid,
            author: author,
            committer: committer,
            noteCommitMessage: noteCommitMessage,
            notesRefName: notesRefName,
            signingCallback: signingCallback
        ).get()
    }

    public func createTag(
        _ name: String,
        target: ObjectType,
        signature: Signature,
        message: String?,
        force: Bool,
        signingCallback: ((String) throws -> String)?
    ) throws -> TagReferenceish {
        let tag = try createTag(
            name,
            target: target,
            signature: signature,
            message: message,
            force: force,
            signingCallback: signingCallback
        ).get()
        return TagReference.annotated("refs/tags/\(tag.name)", tag)
    }

    public func allTags() throws -> [TagReferenceish] {
        return try allTags().get()
    }

    public func push(remote remoteName: String, credentials: Credentials, reference: ReferenceType) throws {
        return try push(remote: remoteName, credentials: credentials, reference: reference).get()
    }

    public func reference(named name: String) throws -> ReferenceType {
        return try reference(named: name).get()
    }

    public func commit(
        tree treeOID: ObjectID,
        parents: [Commitish],
        message: String,
        signature: Signature,
        signingCallback: ((String) throws -> String)?
    ) throws -> Commitish {
        try commit(
            tree: treeOID,
            parents: parents.map { $0 as! Commit },
            message: message,
            signature: signature,
            signingCallback: signingCallback
        ).get()
    }

    public func object(parsing string: String) throws -> ObjectType {
        try object(parsing: string).get()
    }

    public func object(_ oid: ObjectID) throws -> ObjectType {
        try object(oid).get()
    }
}

extension Commit.Trailer: Trailerish {
}

extension Commit: Commitish {
    public var trailers: [Trailerish] {
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

extension Internal {
    public static internal(set) var openRepo: ((URL) -> Result<Repositoryish, Error>) = {
        Repository.at($0).map { $0 }.mapError { $0 }
    }

    public static func openRepo(at path: String) throws -> Repositoryish {
        let url = URL(filePath: path, directoryHint: .isDirectory)
        return try Self.openRepo(url).get()
    }

    public static var defaultGitConfig: (any Configish)? = (try? Config.default())
}

extension Config: Configish {
    public static var defaultConfig: Config {
        get throws {
            try Self.default()
        }
    }

    public var global: Config {
        get throws {
            try Self.default()
        }
    }
}
