//
//  MockGit.swift
//  
//
//  Created by John Biggs on 10.10.23.
//

import Foundation
import LHCInternal
import System
@testable import LHC
@testable import SwiftGit2

struct MockCommit: Commitish, Identifiable {
    static var type: GitObjectType = .commit

    var oid: ObjectID
    var parentOIDs: [ObjectID]
    var author: Signature
    var committer: Signature
    var message: String
    var date: Date

    var trailers: [ConventionalCommit.Trailer] {
        (try? ConventionalCommit(message: message).trailers) ?? []
    }

    var id: ObjectID {
        oid
    }

    init(
        oid: ObjectID,
        parentOIDs: [ObjectID],
        author: Signature,
        committer: Signature,
        message: String,
        date: Date
    ) {
        self.oid = oid
        self.parentOIDs = parentOIDs
        self.author = author
        self.committer = committer
        self.message = message
        self.date = date
    }

    init(_ pointer: OpaquePointer) {
        fatalError("Don't try to init a MockCommit from an OpaquePointer, please.")
    }
}

struct MockBranch: Branchish, Hashable {
    var name: String
    var longName: String
    var oid: ObjectID

    var shortName: String? {
        name
    }
}

struct MockTag: Tagish {
    static var type: GitObjectType = .tag

    var name: String
    var oid: ObjectID
    var tagger: Signature
    var target: Pointer
    var message: String

    init(name: String, oid: ObjectID, tagger: Signature, target: Pointer, message: String) {
        self.name = name
        self.oid = oid
        self.tagger = tagger
        self.target = target
        self.message = message
    }

    init(_ pointer: OpaquePointer) {
        fatalError("Not implemented")
    }
}

enum MockTagReference: TagReferenceish {
    case lightweight(String, ObjectID)
    case annotated(String, MockTag)

    var longName: String {
        switch self {
        case .lightweight(let name, _), .annotated(let name, _):
            return name
        }
    }

    var shortName: String? {
        String(longName["refs/tags/".endIndex...])
    }

    var oid: ObjectID {
        switch self {
        case .lightweight(_, let oid):
            return oid
        case .annotated(_, let tag):
            return tag.target.oid
        }
    }

    var tagOid: ObjectID? {
        guard case .annotated(_, let mockTag) = self else {
            return nil
        }

        return mockTag.oid
    }

    var message: String? {
        switch self {
        case .annotated(_, let tag):
            return tag.message
        default:
            return nil
        }
    }
}

typealias MockConfig = [String: Any]
extension MockConfig: Configish {
    public static func `default`() throws -> Dictionary<Key, Value> {
        [:]
    }

    func get<T>(as type: T.Type, name: String) throws -> T {
        if let value = self[name] as? T {
            return value
        }
        throw GitError(code: .notFound, detail: .config, description: "Mock config: key '\(name)' not found")
    }

    mutating func set<T>(_ value: T, forKey key: String) throws {
        self[key] = value
    }

    public func get(_ type: Bool.Type, _ name: String) throws -> Bool {
        try get(as: type, name: name)
    }

    public func get(_ type: Int32.Type, _ name: String) throws -> Int32 {
        try get(as: type, name: name)
    }

    public func get(_ type: Int64.Type, _ name: String) throws -> Int64 {
        try get(as: type, name: name)
    }

    public func get(_ type: String.Type, _ name: String) throws -> String {
        try get(as: type, name: name)
    }

    public func get(_ type: FilePath.Type, _ name: String) throws -> FilePath {
        try get(as: type, name: name)
    }

    public mutating func set(_ name: String, value: Bool) throws {
        try set(value, forKey: name)
    }

    public mutating func set(_ name: String, value: Int32) throws {
        try set(value, forKey: name)
    }

    public mutating func set(_ name: String, value: Int64) throws {
        try set(value, forKey: name)
    }

    public mutating func set(_ name: String, value: String) throws {
        try set(value, forKey: name)
    }

    public var global: Self {
        try! Self.default()
    }
}

struct MockRepository: Repositoryish {

    var defaultSignature: Signature = .cookie
    var defaultNotesRefName: String = "refs/notes/commits"

    public var config: any Configish = MockConfig()
    var objects: [OID: MockCommit]
    var notes: [OID: Note]
    var tags: [MockTagReference]
    var localBranches: [MockBranch: [MockCommit]]
    var remoteBranches: [MockBranch: [MockCommit]]
    var pushes: [(remoteName: String, ReferenceType)] = []

    var head: any ReferenceType

    func allTags() throws -> [TagReferenceish] {
        tags
    }

    func HEAD() throws -> ReferenceType {
        head
    }

    mutating func setHEAD(_ oid: ObjectID) throws {
        if let branch = localBranches.keys.first(where: { $0.oid == oid }) {
            head = branch
        } else if let branch = remoteBranches.keys.first(where: { $0.oid == oid }) {
            head = branch
        } else if let tag = tags.first(where: { $0.oid == oid }) {
            head = tag
        } else {
            throw GitError(code: .notFound, detail: .object, description: "Unknown object \(oid)")
        }

        MockRepository.repoUpdated?(self)
    }

    func commit(_ oid: ObjectID) throws -> Commitish {
        guard let object = objects[oid] else {
            throw GitError(code: .notFound, detail: .object, description: "Unknown object \(oid)")
        }
        return object
    }

    func localBranch(named name: String) throws -> Branchish {
        guard let branch = localBranches.first(where: { $0.key.name == name}) else {
            throw GitError(code: .notFound, detail: .reference, description: "Unknown branch \(name)")
        }
        return branch.key
    }

    func remoteBranch(named name: String) throws -> Branchish {
        guard let branch = remoteBranches.first(where: { $0.key.name == name}) else {
            throw GitError(code: .notFound, detail: .reference, description: "Unknown branch \(name)")
        }
        return branch.key
    }

    func tag(named name: String) throws -> TagReferenceish {
        guard let tag = tags.first(where: { $0.name == name }) else {
            throw GitError(code: .notFound, detail: .tag, description: "Unknown tag \(name)")
        }
        return tag
    }

    func tag(_ oid: ObjectID) throws -> Tagish {
        guard let tag = tags.compactMap({ (tagReference: MockTagReference) -> Tagish? in
            guard case let .annotated(_, tag) = tagReference else { return nil }
            return tag
        }).filter({
            $0.oid == oid
        }).first else {
            throw GitError(code: .notFound, detail: .tag, description: "Unknown tag \(oid)")
        }

        return tag
    }

    func note(for oid: ObjectID, notesRef: String?) throws -> Note {
        guard let note = notes[oid] else {
            throw GitError(code: .notFound, detail: .object, description: "No note found for \(oid)")
        }
        return note
    }

    mutating func createNote(
        for oid: ObjectID,
        message: String,
        author: Signature,
        committer: Signature,
        noteCommitMessage: String?,
        notesRefName: String?,
        force: Bool,
        signingCallback: Repository.SigningCallback?
    ) throws -> Note {
        guard force || (notes[oid] == nil) else {
            throw GitError(code: .exists, detail: .object, description: "Note already exists for \(oid)")
        }
        let note = Note(
            oid: oid,
            author: author,
            committer: committer,
            message: message
        )
        notes[oid] = note
        return note
    }

    mutating func removeNote(
        for oid: ObjectID,
        author: Signature,
        committer: Signature,
        noteCommitMessage: String?,
        notesRefName: String?,
        signingCallback: Repository.SigningCallback?
    ) throws {
        notes[oid] = nil
    }

    mutating func createTag(_ name: String, target: ObjectType, signature: Signature, message: String?, force: Bool, signingCallback: Repository.SigningCallback?) throws -> Tagish {
        
        guard !tags.contains(where: { $0.name == name }) else {
            throw GitError(code: .exists, detail: .tag, description: "\(name) already exists.")
        }

        guard let commit = target as? MockCommit else {
            fatalError("Invariant violation: target is not a mock commit object")
        }

        let tag: MockTagReference = .annotated(name: name, message: message ?? "", tagging: commit)
        tags.append(tag)

        MockRepository.repoUpdated?(self)

        guard case .annotated(_, let mockTag) = tag else {
            fatalError("Something horrible has happened")
        }
        return mockTag
    }

    mutating func commit(tree treeOID: ObjectID, parents: [Commitish], message: String, signature: Signature, signingCallback: Repository.SigningCallback?) throws -> Commitish {
        let commit = MockCommit(
            oid: .random(),
            parentOIDs: parents.map(\.oid),
            author: signature,
            committer: signature,
            message: message,
            date: .now
        )

        objects[commit.oid] = commit
        return commit
    }

    mutating func push(remote remoteName: String, options: PushOptions, reference: ReferenceType) throws {
        switch reference {
        case let localBranch as MockBranch:
            guard let commit = try commit(localBranch.oid) as? MockCommit else {
                fatalError("Invariant violation: commit is not a mock object")
            }

            let mockRemote: MockBranch = .branch(
                name: "refs/remotes/\(remoteName)/\(localBranch.name)",
                head: commit
            )

            remoteBranches[mockRemote] = try commits(from: localBranch.oid, since: nil).map {
                guard let commit = $0 as? MockCommit else {
                    fatalError("Invariant violation: commit is not a mock object")
                }
                return commit
            }
            fallthrough
        case is MockTagReference:
            pushes.append((remoteName, reference))
        default:
            fatalError("Test invariant violation: unhandled type \(type(of: reference)) in \(#function)")
        }

        MockRepository.repoUpdated?(self)
    }

    func references() throws -> [ReferenceType] {
        Array(localBranches.keys) + Array(remoteBranches.keys) + tags
    }

    func references(withPrefix prefix: String) throws -> [ReferenceType] {
        try references().filter { $0.longName.hasPrefix(prefix) }
    }

    func blob(_ oid: ObjectID) throws -> Blob {
        fatalError("Not yet implemented")
    }

    func reference(named name: String) throws -> ReferenceType {
        guard let first = try references().first(where: {
            $0.longName == name
        }) else {
            throw GitError(code: .notFound, detail: .reference, description: "Reference not found")
        }
        return first
    }

    func object(parsing string: String) throws -> ObjectType {
        guard let oid = ObjectID(string: string) else {
            fatalError("OID parsing is not implemented :)")
        }
        return try object(oid)
    }

    func object(_ oid: ObjectID) throws -> ObjectType {
        if let tagReference = tags.first(where: { $0.tagOid == oid }),
           case let .annotated(_, tag) = tagReference {
            return tag
        } else if let object = objects[oid] {
            return object
        } else {
            throw GitError(code: .notFound, detail: .object, description: "Mock object not found.")
        }
    }

    func readNoteCommit(for oid: ObjectID, commit: Commitish) throws -> Note {
        fatalError("Not yet implemented")
    }
}

// MARK: - Test Data

extension Signature {
    static let cookie: Self = .init(
        name: "Cookie Monster",
        email: "cookie.monster@sesame.street"
    )
}

extension MockCommit {
    static func mock(
        oid: ObjectID = .random(),
        parentOIDs: [ObjectID] = [],
        author: Signature = .cookie,
        committer: Signature = .cookie,
        message: String,
        date: Date = .distantPast
    ) -> Self {
        self.init(
            oid: oid,
            parentOIDs: parentOIDs,
            author: author,
            committer: committer,
            message: message,
            date: date
        )
    }

    static let subjectWithInvalidFormat: Self = .mock(
        parentOIDs: [Self.developCommit(indexFromRoot: 2).oid],
        message: "Triceratops were, like, super big dinosaurs, ya dig?",
        date: .now.addingTimeInterval(-.minutes(2))
    )

    static let subjectWithInvalidCategory: Self = .mock(
        parentOIDs: [Self.developCommit(indexFromRoot: 2).oid],
        message: "triceratops(dinosaurs): what an absolute unit",
        date: .now.addingTimeInterval(-.minutes(3))
    )

    static let hotfixNotOnDevelop: Self = .mock(
        parentOIDs: [MockTagReference.first.oid],
        message: "fix: hotfix off of a non-develop branch",
        date: .now.addingTimeInterval(-.days(1))
    )

    static let withProjectId: Self = .mock(
        parentOIDs: [Self.developCommit(indexFromRoot: 2).oid],
        message: """
            fix(test): fourth commit

            This commit also has project ids, make sure the branch matches.

            Project-Id: TEST-1234
            """,
        date: .now.addingTimeInterval(-.minutes(5))
    )

    static let withMultipleProjectIds: Self = .mock(
        parentOIDs: [Self.developCommit(indexFromRoot: 2).oid],
        message: """
            fix(test): fourth commit

            This commit also has project ids, make sure the branch matches.

            Project-Id: TEST-1234
            Project-Id: TEST-5678
            """,
        date: .now.addingTimeInterval(-.minutes(4))
    )

    static let withProjectIdFromDifferentProject: Self = .mock(
        parentOIDs: [Self.developCommit(indexFromRoot: 2).oid],
        message: """
            fix(fix): fixy fix

            Project-Id: OTHER-1234
            """
    )

    static let withMultipleProjectIdsFromDifferentProjects: Self = .mock(
        parentOIDs: [Self.developCommit(indexFromRoot: 2).oid],
        message: """
            fix(test): fourth commit

            This commit also has project ids, make sure the branch matches.

            Project-Id: TEST-1234
            Project-Id: TEST-5678
            Project-Id: OTHER-9012
            """,
        date: .now.addingTimeInterval(-.minutes(3))
    )

    // TODO: "BREAKING CHANGE" still doesn't seem to parse correctly. Leave it with a hyphen for now.
    static let developCommits = link([
        .mock(
            message: """
                build(dependencies): integrate library 3.2.1

                this is unfortunately a breaking change because the library is not a
                very nice one.

                BREAKING-CHANGE: this library is not good
                Project-Id: TEST-9999
                """
         ),
        .mock(message: "feat: a feature worthy of a release"),
        .mock(message: "fix: this is another prerelease commit"),
        .mock(message: "fix: this is the first prerelease commit"),
        .mock(
            message: """
                fix: more fixes

                this commit is tagged with a release tag on develop.
                """
        ),
        .mock(
            message: """
                fix(test): third commit

                this commit happens to have a body, but it also has
                some trailers, which is also pretty cool!

                Project-Id: TEST-8192
                """
        ),
        .mock(
            message: """
                feat: second commit

                this commit actually happens to have a body.
                how cool is that!?
                """
        ),
        .mock(message: "feat: initial commit")
    ])

    private static func link(_ commits: [MockCommit]) -> [Self] {
        let oids = commits.map(\.oid).enumerated()
        let now = Date.now
        return oids.map {
            let index = $0.offset
            var commit = commits[index]
            guard index != commits.count - 1 else {
                return commit
            }
            commit.parentOIDs.append(commits[index + 1].oid)

            let factor = 3
            let range = Range<TimeInterval>(uncheckedBounds: (
                .days(factor * index),
                .days(factor * (index + 1))
            ))
            commit.date = now.addingTimeInterval(-.random(in: range))
            return commit
        }
    }

    static func developCommit(indexFromRoot: Int) -> Self {
        precondition(0 <= indexFromRoot && indexFromRoot < developCommits.count, "Invalid commit index")
        return developCommits[developCommits.count - indexFromRoot - 1]
    }

    static let all: [ObjectID: Self] = {
        let commits: [Self] = developCommits + [
            .hotfixNotOnDevelop,
            .subjectWithInvalidFormat,
            .subjectWithInvalidCategory,
            .withProjectId,
            .withMultipleProjectIds,
            .withMultipleProjectIdsFromDifferentProjects,
            .withProjectIdFromDifferentProject
        ]

        return commits.reduce(into: [:]) { (partialResult: inout [OID: Self], commit: MockCommit) in
            partialResult[commit.oid] = commit
        }
    }()

    static func oid(_ oid: ObjectID) -> Self? {
        all[oid]
    }
}

extension MockBranch {
    static let develop: Self = .branch(name: "develop", head: .developCommit(indexFromRoot: MockCommit.developCommits.count - 1))
    static let originDevelop: Self = .branch(name: "origin/develop", head: .developCommit(indexFromRoot: MockCommit.developCommits.count - 1))

    static let branchOffOfEarlyDevelop: Self = .branch(name: "earlyDevelop", head: .developCommit(indexFromRoot: 2))
    static let branchWithInvalidSubject: Self = .branch(name: "invalidSubject", head: .subjectWithInvalidFormat)
    static let branchWithInvalidCategory: Self = .branch(name: "invalidCommitCategory", head: .subjectWithInvalidCategory)

    static let branchWithFullProjectIdInLastComponent: Self = .branch(name: "abc/test/TEST-1234-this-is-a-good-branch", head: .withProjectId)
    static let branchWithMismatchedFullProjectIdInLastComponent: Self = .branch(name: "abc/test/TEST-5678-this-is-a-bad-branch", head: .withProjectId)
    static let branchWithPartialProjectIdInLastComponent: Self = .branch(name: "abc/test/1234-this-is-a-good-branch", head: .withProjectId)
    static let branchWithMismatchedPartialProjectIdInLastComponent: Self = .branch(name: "abc/test/5678-this-is-a-bad-branch", head: .withProjectId)
    static let branchWithOtherProjectId: Self = .branch(name: "abc/test/OTHER-1234-this-is-okay-if-it-still-matches", head: .withProjectIdFromDifferentProject)
    static let branchWithMultipleProjectIds: Self = .branch(name: "abc/test/TEST-1234-TEST-5678-OTHER-9012-multiple-project-ids", head: .withMultipleProjectIdsFromDifferentProjects)

    static let hotfix: Self = .branch(name: "hotfix", head: .hotfixNotOnDevelop)

    static func branch(name: String, head: MockCommit) -> Self {
        .init(
            name: name,
            longName: name.starts(with: "origin/") ?
                "refs/remotes/\(name)" : "refs/heads/\(name)",
            oid: head.oid
        )
    }

    static let all: [Self] = [
        .develop,
        .originDevelop,
        .hotfix,
        .branchOffOfEarlyDevelop,
        .branchWithInvalidSubject,
        .branchWithInvalidCategory,
        .branchWithFullProjectIdInLastComponent,
        .branchWithPartialProjectIdInLastComponent,
        .branchWithMismatchedFullProjectIdInLastComponent,
        .branchWithMismatchedPartialProjectIdInLastComponent,
        .branchWithOtherProjectId,
        .branchWithMultipleProjectIds
    ]
}

extension MockTagReference {
    static let first: Self = .annotated(name: "0.0.1", tagging: .developCommit(indexFromRoot: 3))
    static let notAVersion: Self = .annotated(name: "not-a-version", tagging: .developCommit(indexFromRoot: 2))
    static let firstPrerelease: Self = .annotated(name: "0.0.2-rc.1", tagging: .developCommit(indexFromRoot: 4))
    static let secondPrerelease: Self = .annotated(name: "0.0.2-rc.2", tagging: .developCommit(indexFromRoot: 5))
    static let secondRelease: Self = .annotated(name: "0.1.0", tagging: .developCommit(indexFromRoot: 6))
    static let thirdReleaseNotOnDevelop: Self = .annotated(name: "0.0.2", tagging: .hotfixNotOnDevelop)

    static let firstTrainRelease: Self = .annotated(name: "train/0.1.0", tagging: .developCommit(indexFromRoot: 2))
    static let firstTrainPrerelease: Self = .annotated(name: "train/0.1.1-rc.1", tagging: .developCommit(indexFromRoot: 3))
    static let secondTrainRelease: Self = .annotated(name: "train/0.1.1", tagging: .developCommit(indexFromRoot: 5))

    static func lightweight(name: String, tagging commit: MockCommit) -> Self {
        .lightweight("refs/tags/\(name)", commit.oid)
    }

    static func annotated(name: String, message: String? = nil, tagging commit: MockCommit) -> Self {
        let longName = "refs/tags/\(name)"
        return .annotated(
            longName,
            .init(
                name: name,
                oid: .random(),
                tagger: .cookie,
                target: .commit(commit.oid),
                message: message ?? "Tag \(name)"
            )
        )
    }

    static let all: [Self] = [
        .first,
        .notAVersion,
        .firstPrerelease,
        .secondPrerelease,
        .secondRelease,
        .thirdReleaseNotOnDevelop,
        .firstTrainRelease,
        .firstTrainPrerelease,
        .secondTrainRelease,
    ]
}

extension MockRepository {
    /// - Note: Because this is pass-by-value, modifications only work at the *start* of a test case.
    static var mock: Self = .init(
        objects: MockCommit.all,
        notes: [:],
        tags: MockTagReference.all,
        localBranches: MockBranch.all
            .filter({ $0.longName.starts(with: "refs/heads") })
            .reduce(into: [:], { $0[$1] = .chase(oid: $1.oid) }),
        remoteBranches: MockBranch.all
            .filter({ $0.longName.starts(with: "refs/remotes") })
            .reduce(into: [:], { $0[$1] = .chase(oid: $1.oid) }),
        head: MockBranch.develop
    )

    static var repoUpdated: ((MockRepository) -> ())?
}

extension Array<MockCommit> {
    static func chase(oid: OID) -> [MockCommit] {
        var result: [MockCommit] = []
        var frontier = [oid]
        while !frontier.isEmpty {
            let commits = frontier.compactMap { (oid: OID) -> MockCommit? in
                guard let commit = MockCommit.oid(oid) else {
                    assertionFailure("Commit pointed to oid \(oid) which does not appear in any data structure")
                    return nil
                }
                return commit
            }

            result += commits
            frontier = commits.flatMap { $0.parentOIDs }
        }

        return result.sorted {
            $0.date > $1.date
        }
    }
}
