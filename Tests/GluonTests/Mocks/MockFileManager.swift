//
//  File.swift
//  
//
//  Created by John Biggs on 10.10.23.
//

import Foundation
@testable import gluon

struct MockFileManager: FileManagerish {
    var currentDirectoryPath: String
    var homeDirectoryForCurrentUser: URL

    var root: MockFile

    func tree(from path: String) -> [MockFile] {
        let url = URL(string: path)!

        var components = url.pathComponents
        var tree = [root]

        while components.count > 0 {
            let component = components.removeFirst()
            switch tree.last {
            case .file:
                return tree
            case let .directory(name, contents):
                guard name == component else { return [] }
                // If there aren't any other things to recurse into, we're done.
                guard let first = components.first else { return tree }
                guard let child = contents.first(where: { $0.name == first }) else { return [] }
                tree.append(child)
            default: // nil
                preconditionFailure("Invariant violation")
            }
        }
        return []
    }

    mutating func setNode(_ node: MockFile?, atPath path: String) throws {
        var tree = tree(from: path)
        guard !tree.isEmpty else {
            throw POSIXError(.ENOENT)
        }

        var node = node
        while let last = tree.last {
            if node != nil {
                // We want to set the node as a child of the current path.
                guard case .directory(let name, var contents) = last else {
                    fatalError("Invariant violation: can't put a file in a file")
                }

                contents.removeAll(where: { $0.name == node?.name })

                contents.append(node!)
                node = .directory(name: name, contents: contents)
            } else {
                // Special case: we've called `setNode(nil, atPath:)`, which means that
                // we want to remove a file.
                // Traverse one more level up in the tree to get the containing directory.
                tree.removeLast()
                guard case .directory(let parentName, var parentContents) = tree.last else {
                    fatalError("Invariant violation: tried to set filesystem root to nil")
                }
                guard let index = parentContents.firstIndex(where: { $0.name == last.name }) else {
                    throw POSIXError(.ENOENT)
                }
                parentContents.remove(at: index)
                node = .directory(name: parentName, contents: parentContents)
            }

            tree.removeLast()
        }

        root = node!
    }

    func fileExists(atPath path: String) -> Bool {
        !tree(from: path).isEmpty
    }

    func fileExists(atPath path: String, isDirectory: inout Bool?) -> Bool {
        let tree = tree(from: path)
        guard !tree.isEmpty else { return false }

        if case .directory = tree.last {
            isDirectory = true
        } else {
            isDirectory = false
        }

        return true
    }

    mutating func createFile(atPath path: String, contents data: Data?, attributes attr: [FileAttributeKey : Any]?) -> Bool {
        guard let url = URL(string: path) else { return false }

        do {
            guard !fileExists(atPath: path) else {
                return false
            }

            try setNode(
                .file(
                    name: url.lastPathComponent,
                    contents: data
                ),
                atPath: url.deletingLastPathComponent().path()
            )
            return true
        } catch {
            return false
        }
    }

    mutating func removeItem(atPath path: String) throws {
        try setNode(nil, atPath: path)
    }

    func contents(atPath path: String) -> Data? {
        switch tree(from: path).last {
        case let .file(_, contents):
            return contents
        default:
            return nil
        }
    }

    indirect enum MockFile {
        case directory(name: String, contents: [MockFile])
        case file(name: String, contents: Data?)

        var name: String {
            switch self {
            case let .file(name, _), let .directory(name, _):
                return name
            }
        }
    }

    static let mock: Self = .init(
        currentDirectoryPath: "/Users/test/repo",
        homeDirectoryForCurrentUser: URL(string: "/Users/test")!,
        root: .directory(
            name: "/",
            contents: [
                .directory(name: "Users", contents: [
                    .directory(name: "test", contents: [
                        .directory(name: "repo", contents: [
                            .directory(name: ".git", contents: []),
                            .file(name: "file", contents: nil),
                            .file(name: ".gluon.yml", contents: .configFile)
                        ])
                    ])
                ])
            ]
        )
    )
}
