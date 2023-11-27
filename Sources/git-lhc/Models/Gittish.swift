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

typealias ObjectID = OID

protocol Repositoryish {
    var defaultSignature: Signature { get throws }

    func HEAD() throws -> ReferenceType
    mutating func setHEAD(_ oid: ObjectID) throws
    func commit(_ oid: ObjectID) throws -> Commitish
    func commits(in: Branchish) -> CommitishIterator
    func localBranch(named: String) throws -> Branchish
    func remoteBranch(named: String) throws -> Branchish
    func tag(named: String) throws -> TagReferenceish
    func tag(_ oid: ObjectID) throws -> Tagish
    mutating func createTag(_ name: String, target: ObjectType, signature: Signature, message: String) throws -> TagReferenceish
    func allTags() throws -> [TagReferenceish]
    mutating func push(remote remoteName: String, credentials: Credentials, reference: ReferenceType) throws
    mutating func commit(tree treeOID: ObjectID, parents: [Commitish], message: String, signature: Signature) throws -> Commitish
}

extension Repositoryish {
    func currentBranch() throws -> Branchish? {
        if let branchName = LHC.branchName,
           let branch = (try? localBranch(named: branchName)) ??
                        (try? remoteBranch(named: branchName)) {
            return branch
        }

        return try? HEAD() as? Branchish
    }

    func oid(for refName: String) throws -> ObjectID? {
        if let oid = ObjectID(string: refName) { return oid }
        if let tag = try? tag(named: refName) { return tag.oid }
        if let local = try? localBranch(named: refName) { return local.oid }
        if let remote = try? remoteBranch(named: refName) { return remote.oid }

        throw RepositoryError.invalidReference(refName)
    }

    func commits(since start: ObjectID?) throws -> (branch: Branchish?, commits: [Commitish]) {
        if let branch = try? currentBranch() {
            return try (branch, commits(on: branch, since: start))
        }

        let head = try HEAD()
        return try (head as? Branchish, commits(from: head.oid, since: start))
    }

    func commits(on branch: Branchish, since start: ObjectID?) throws -> [Commitish] {
        var result: [Commitish] = []
        let branchCommits = commits(in: branch)

        for maybeCommit in branchCommits {
            guard let commit = try? maybeCommit.get() else { break }
            guard commit.oid != start else { return result }
            result.append(commit)
        }

        guard let start else { return result }
        throw RepositoryError.referenceNotFoundStartingFromLeaf(reference: start, leaf: branch.oid)
    }

    func commits(from oid: ObjectID, since start: ObjectID?) throws -> [Commitish] {
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
                    return try self.commit($0)
                }

            result += commits
            frontier.forEach { seen.insert($0) }
            frontier = commits.flatMap { $0.parentOIDs }
        }

        guard let start else { return result }
        throw RepositoryError.referenceNotFoundStartingFromLeaf(reference: start, leaf: oid)
    }

    func isReachable(_ target: ObjectID, from leaf: ObjectID) throws -> Bool {
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
}

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

protocol Branchish: ReferenceType {
}

extension Branchish {
    var name: String {
        shortName ?? longName
    }
}

protocol TagReferenceish: ReferenceType {
    var message: String? { get }
}

extension TagReferenceish {
    var name: String {
        shortName ?? longName
    }
}

protocol Tagish {
    var oid: ObjectID { get }
    var target: Pointer { get }
    var name: String { get }
    var tagger: Signature { get }
    var message: String { get }
}

protocol Commitish: ObjectType, CustomStringConvertible {
    var parentOIDs: [ObjectID] { get }

    var author: Signature { get }
    var committer: Signature { get }
    var message: String { get }
    var date: Date { get }

    var trailers: [Trailerish] { get throws }
}

extension Signature: CustomStringConvertible {
    public var description: String {
        "\(name) <\(email)>"
    }
}

extension Commitish {
    public var description: String {
        let dateFormatter = DateFormatter()
        // Sun Nov 12 16:20:42 2023 +0100
        dateFormatter.dateFormat = "EEE MMM d HH:MM:SS YYYY Z"

        return """
        commit \(oid.description)
        Author: \(author.description)
        Date:   \(dateFormatter.string(from: date))

        \(message.indented())
        """
    }
}

protocol Trailerish {
    var key: String { get }
    var value: String { get }
}
