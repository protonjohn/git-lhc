//
//  Attributes.swift
//  
//
//  Created by John Biggs on 16.01.24.
//

import SwiftGit2
import Foundation
import LHCInternal

extension Repositoryish {
    /// Get the list of commits that added or removed a given attribute key for a given object.
    public func attributeLog(key: String, target: ObjectID, refName: String) throws -> [AttributeLogEntry] {
        // Get all of the note commits for a given object that have defined a given attribute.
        return try noteCommits(on: try reference(named: refName), for: target)
            .compactMap {
                guard let parent = $0.parentOIDs.first,
                      let parentCommit = try? commit(parent),
                      let parentNote = try? readNoteCommit(for: target, commit: parentCommit) else {
                    // The common case: this is the first attribute added for a given object
                    guard let attributes = $1?.attributes.trailers,
                          let first = attributes.first else { return nil }

                    return .init(
                        action: .add,
                        key: first.key,
                        value: first.value,
                        commit: $0
                    )
                }

                if let value = $1?.attributes.trailers?[key] {
                    if parentNote.attributes.trailers?[key] == nil {
                        return .init(action: .add, key: key, value: value, commit: $0)
                    }
                } else if let parentValue = parentNote.attributes.trailers?[key] {
                    return .init(action: .remove, key: key, value: parentValue, commit: $0)
                }

                return nil
            }
    }
}

public struct AttributeLogEntry: CustomStringConvertible {
    public enum Action: String {
        case add
        case remove
    }

    public let action: Action
    public let key: String
    public let value: String
    public let commit: Commitish

    public var description: String {
        let subject = commit.message.split(separator: "\n", maxSplits: 1).first!
        let longHash = commit.oid.description
        let shortHash = longHash.prefix(upTo: longHash.index(longHash.startIndex, offsetBy: 8))

        let set = action == .add ? "+" : "-"
        return "\(set)\(key): \(value)\n\(shortHash) \(subject)"
    }
}

extension Note {
    public var attributes: (body: String, trailers: [ConventionalCommit.Trailer]?) {
        guard let (body, trailers) = try? ConventionalCommit.Trailer.trailers(from: message),
              !trailers.isEmpty else {
            return (message, [])
        }

        return (body, trailers)
    }
}
