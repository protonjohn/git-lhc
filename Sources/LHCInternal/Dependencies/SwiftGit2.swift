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
        return CommitishIterator(commits(in: branch as! Branch))
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

    public func createTag(_ name: String, target: ObjectType, signature: Signature, message: String) throws -> TagReferenceish {
        let tag = try createTag(name, target: target, signature: signature, message: message).get()
        return TagReference.annotated("refs/tags/\(tag.name)", tag)
    }

    public func allTags() throws -> [TagReferenceish] {
        return try allTags().get()
    }

    public func push(remote remoteName: String, credentials: Credentials, reference: ReferenceType) throws {
        return try push(remote: remoteName, credentials: credentials, reference: reference).get()
    }

    public func commit(
        tree treeOID: ObjectID,
        parents: [Commitish],
        message: String,
        signature: Signature
    ) throws -> Commitish {
        try commit(tree: treeOID, parents: parents.map { $0 as! Commit }, message: message, signature: signature).get()
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
}
