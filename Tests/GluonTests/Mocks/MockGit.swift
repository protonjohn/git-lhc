//
//  MockGit.swift
//  
//
//  Created by John Biggs on 10.10.23.
//

import Foundation
import SwiftGit2
@testable import gluon

struct MockCommit: Commitish, Identifiable {
    var oid: ObjectID
    var parentOIDs: [ObjectID]
    var author: Signature
    var committer: Signature
    var message: String
    var date: Date

    var trailers: [Trailerish] {
        (try? ConventionalCommit(message: message).trailers) ?? []
    }

    var id: ObjectID {
        oid
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
    var name: String
    var oid: ObjectID
    var tagger: Signature
    var target: Pointer
    var message: String
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
            return tag.oid
        }
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

class MockCommitishIterator: CommitishIterator {
    let commits: [MockCommit]

    var error: Error?
    var index = 0

    init(commits: [MockCommit]) {
        self.commits = commits
        super.init(nil)
    }

    override func next() -> CommitishIterator.Element? {
        if let error {
            return .failure(error)
        }

        let current = index
        guard current < commits.count else { return nil }
        defer { index += 1 }

        return .success(commits[current])
    }
}

struct MockRepository: Repositoryish {
    var objects: [OID: MockCommit]
    var tags: [MockTagReference]
    var localBranches: [MockBranch: [MockCommit]]
    var remoteBranches: [MockBranch: [MockCommit]]

    var head: any ReferenceType

    func allTags() throws -> [TagReferenceish] {
        tags
    }

    func commits(in branch: Branchish) -> CommitishIterator {
        MockCommitishIterator(
            commits: localBranches[branch as! MockBranch] ??
                remoteBranches[branch as! MockBranch] ??
                []
        )
    }

    func HEAD() throws -> ReferenceType {
        head
    }

    enum MockError: Error {
        case unknownOID(OID)
        case unknownBranch(String)
        case unknownTag(String)
        case unknownTagOID(ObjectID)
    }

    mutating func setHEAD(_ oid: ObjectID) throws {
        if let branch = localBranches.keys.first(where: { $0.oid == oid }) {
            head = branch
        } else if let branch = remoteBranches.keys.first(where: { $0.oid == oid }) {
            head = branch
        } else if let tag = tags.first(where: { $0.oid == oid }) {
            head = tag
        } else {
            throw MockError.unknownOID(oid)
        }
    }

    func commit(_ oid: ObjectID) throws -> Commitish {
        guard let object = objects[oid] else {
            throw MockError.unknownOID(oid)
        }
        return object
    }

    func localBranch(named name: String) throws -> Branchish {
        guard let branch = localBranches.first(where: { $0.key.name == name}) else {
            throw MockError.unknownBranch(name)
        }
        return branch.key
    }

    func remoteBranch(named name: String) throws -> Branchish {
        guard let branch = remoteBranches.first(where: { $0.key.name == name}) else {
            throw MockError.unknownBranch(name)
        }
        return branch.key
    }

    func tag(named name: String) throws -> TagReferenceish {
        guard let tag = tags.first(where: { $0.name == name }) else {
            throw MockError.unknownTag(name)
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
            throw MockError.unknownTagOID(oid)
        }

        return tag
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

                Git-Trailer: present
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
            .withMultipleProjectIdsFromDifferentProjects
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
        .branchWithMismatchedPartialProjectIdInLastComponent
    ]
}

extension MockTagReference {
    static let first: Self = .lightweight(name: "0.0.1", tagging: .developCommit(indexFromRoot: 3))
    static let notAVersion: Self = .lightweight(name: "not-a-version", tagging: .developCommit(indexFromRoot: 2))
    static let firstPrerelease: Self = .lightweight(name: "0.0.2-202310131751", tagging: .developCommit(indexFromRoot: 4))
    static let secondPrerelease: Self = .lightweight(name: "0.0.2-202310131802", tagging: .developCommit(indexFromRoot: 5))
    static let secondRelease: Self = .lightweight(name: "0.1.0", tagging: .developCommit(indexFromRoot: 6))
    static let thirdReleaseNotOnDevelop: Self = .lightweight(name: "0.0.2", tagging: .hotfixNotOnDevelop)

    static let firstTrainRelease: Self = .lightweight(name: "train/0.1.0", tagging: .developCommit(indexFromRoot: 2))
    static let firstTrainPrerelease: Self = .lightweight(name: "train/0.1.1-202310141157", tagging: .developCommit(indexFromRoot: 3))
    static let secondTrainRelease: Self = .lightweight(name: "train/0.1.1-202310141200", tagging: .developCommit(indexFromRoot: 5))

    static func lightweight(name: String, tagging commit: MockCommit) -> Self {
        .lightweight("refs/tags/\(name)", commit.oid)
    }

    static func annotated(name: String, message: String, tagging commit: MockCommit) -> Self {
        let longName = "refs/tags/\(name)"
        return .annotated(
            longName,
            .init(
                name: longName,
                oid: commit.oid,
                tagger: .cookie,
                target: .commit(commit.oid),
                message: message
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
    static var mock: Self = .init(
        objects: MockCommit.all,
        tags: MockTagReference.all,
        localBranches: MockBranch.all
            .filter({ $0.longName.starts(with: "refs/heads") })
            .reduce(into: [:], { $0[$1] = .chase(oid: $1.oid) }),
        remoteBranches: MockBranch.all
            .filter({ $0.longName.starts(with: "refs/remotes") })
            .reduce(into: [:], { $0[$1] = .chase(oid: $1.oid) }),
        head: MockBranch.develop
    )
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
