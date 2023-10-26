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
        guard #available(macOS 13, *) else { return [] }

        guard let currentDirectory = URL(string: currentDirectoryPath) else {
            return []
        }
        let url = URL(string: path) ?? URL(filePath: path, relativeTo: currentDirectory)

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

    mutating func setNode(_ node: MockFile, atPath path: String) throws {
        var tree = tree(from: path)
        guard !tree.isEmpty else {
            throw MockFileError.noSuchFileOrDirectory(path: path)
        }

        var node = node
        while let last = tree.last {
            switch last {
            case .directory(let name, var contents):
                contents.append(node)
                node = .directory(name: name, contents: contents)
            default:
                fatalError("Invariant violation: can't put a file in a file")
            }

            tree.removeLast()
        }

        root = node
    }

    func fileExists(atPath path: String) -> Bool {
        !tree(from: path).isEmpty
    }

    mutating func createFile(atPath path: String, contents data: Data?, attributes attr: [FileAttributeKey : Any]?) -> Bool {
        guard let url = URL(string: path) else { return false }

        do {
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
                            .file(name: "file", contents: nil),
                            .file(name: ".gluon.yml", contents: .configFile)
                        ])
                    ])
                ])
            ]
        )
    )
}

enum MockFileError: Error {
    case noSuchFileOrDirectory(path: String)
}
