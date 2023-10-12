//
//  Git.swift
//
//
//  Created by John Biggs on 10.10.23.

import Foundation
import SwiftGit2

extension Repository: Repositoryish {
    func HEAD() throws -> ReferenceType {
        return try HEAD().get()
    }

    func setHEAD(_ oid: ObjectID) throws {
        try setHEAD(oid).get()
    }

    func commit(_ oid: ObjectID) throws -> Commitish {
        return try commit(oid).get()
    }

    func commits(in branch: Branchish) -> CommitishIterator {
        return CommitishIterator(commits(in: branch as! Branch))
    }

    func localBranch(named name: String) throws -> Branchish {
        return try localBranch(named: name).get()
    }

    func remoteBranch(named name: String) throws -> Branchish {
        return try remoteBranch(named: name).get()
    }

    func tag(named name: String) throws -> TagReferenceish {
        return try tag(named: name).get()
    }

    func tag(_ oid: ObjectID) throws -> Tagish {
        return try tag(oid).get()
    }

    func allTags() throws -> [TagReferenceish] {
        return try allTags().get()
    }
}

class CommitishIterator: IteratorProtocol, Sequence {
    var wrappedValue: CommitIterator?

    typealias Element = Result<Commitish, Error>
    typealias Iterator = CommitishIterator

    init(_ wrappedValue: CommitIterator?) {
        self.wrappedValue = wrappedValue
    }

    func next() -> Element? {
        wrappedValue?
            .next()?
            .map { $0 }
            .mapError { $0 }
    }
}

extension Commit.Trailer: Trailerish {
}

extension Commit: Commitish {
    var trailers: [Trailerish] {
        get throws {
            try trailers().get()
        }
    }

    var parentOIDs: [ObjectID] {
        parents.map(\.oid)
    }
}

extension Branch: Branchish {
}

extension TagReference: TagReferenceish {
    var message: String? {
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

extension Gluon {
    static var openRepo: ((URL) -> Result<Repositoryish, Error>) = {
        Repository.at($0).map { $0 }.mapError { $0 }
    }
}
