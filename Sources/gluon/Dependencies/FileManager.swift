//
//  FileManager.swift
//  
//
//  Created by John Biggs on 10.10.23.
//

import Foundation

protocol FileManagerish {
    var currentDirectoryPath: String { get }
    var homeDirectoryForCurrentUser: URL { get }

    func fileExists(atPath: String) -> Bool
    func fileExists(atPath: String, isDirectory: inout Bool?) -> Bool
    mutating func removeItem(atPath: String) throws

    func contents(atPath path: String) -> Data?

    mutating func createFile(
        atPath path: String,
        contents data: Data?,
        attributes attr: [FileAttributeKey : Any]?
    ) -> Bool
}

extension FileManagerish {
    mutating func createFile(
        atPath path: String,
        contents data: Data?
    ) -> Bool {
        createFile(atPath: path, contents: data, attributes: nil)
    }
}

extension FileManagerish {
    func traverseUpwardsUntilFinding(fileName: String, startingPoint: String? = nil, isDirectory: Bool = false) -> String? {
        var url: URL
        if let startingPoint {
            guard let startingURL = URL(string: startingPoint) else {
                return nil
            }

            url = startingURL
        } else {
            url = URL(string: currentDirectoryPath)!
        }
        url = url.appending(path: fileName)

        var thisIsDir: Bool?
        while !fileExists(atPath: url.path(), isDirectory: &thisIsDir), isDirectory != thisIsDir {
            url = url.deletingLastPathComponent()

            guard url.path() != "/" &&
                    (try? url.canonicalPath) != "/" else {
                return nil
            }

            let directoryHint: URL.DirectoryHint = isDirectory ? .isDirectory : .notDirectory
            url = url
                .appending(component: "../", directoryHint: .isDirectory)
                .appending(component: fileName, directoryHint: directoryHint)
        }
        return url.path()
    }
}

extension FileManager: FileManagerish {
    func fileExists(atPath path: String, isDirectory: inout Bool?) -> Bool {
        var isDir: ObjCBool = false

        let result = fileExists(atPath: path, isDirectory: &isDir)
        isDirectory = isDir.boolValue

        return result
    }
}

extension Gluon {
    static var fileManager: FileManagerish = FileManager.default
}
