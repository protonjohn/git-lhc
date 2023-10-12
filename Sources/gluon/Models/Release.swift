//
//  Release.swift
//
//  Created by John Biggs on 11.10.23.
//

import Foundation
import Version
import SwiftGit2

struct Release: Codable {
    typealias Category = String

    let versionString: String
    let train: Configuration.Train?
    let tagged: Bool
    let changes: [Category: [Change]]

    let body: String?

    var version: Version? {
        Version(versionString)
    }

    struct Change: Codable {
        let summary: String
        let body: String?
        let commitHash: String
        let projectIds: [String]
    }
}

extension Release {
    init(
        version: Version,
        tagged: Bool,
        train: Configuration.Train?,
        body: String?,
        conventionalCommits: [ConventionalCommit],
        correspondingHashes: [ObjectID]
    ) {
        assert(conventionalCommits.count == correspondingHashes.count, "Array lengths do not match")

        self.versionString = version.description
        self.tagged = tagged
        self.train = train
        self.body = body

        let trailerName = Configuration.configuration
            .branchNameLinting?.projectIdTrailerName

        self.changes = conventionalCommits.enumerated().reduce(into: [:], { result, element in
            let (index, cc) = element
            let header = cc.header

            if result[header.type] == nil {
                result[header.type] = []
            }

            result[header.type]?.append(Change(
                summary: header.summary,
                body: cc.body,
                commitHash: correspondingHashes[index].description,
                projectIds: trailerName == nil ? [] :
                    cc.trailers(named: trailerName!).map(\.value)
            ))
        })
    }
}

extension Release: CustomStringConvertible {
    var description: String {
        var result = "# \(train?.name ?? "Version") \(versionString)\(tagged ? "" : " (Not Tagged)"):\n\n"

        if let body {
            result.append("\(body)\n\n")
        }

        result.append("""
            \(changes.reduce(into: "") { result, category in
                result += "## \(category.key):\n"
                result += category.value.map { "- \($0.summary)" }.joined(separator: "\n")
                result += "\n"
            })
            """
        )

        return result.trimmingCharacters(in: .newlines)
    }
}
