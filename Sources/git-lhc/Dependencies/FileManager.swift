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

    mutating func url(for directory: FileManager.SearchPathDirectory, in domain: FileManager.SearchPathDomainMask, appropriateFor url: URL?, create shouldCreate: Bool) throws -> URL

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

    /// editFile: Spawn an editor session if detected to be running in a terminal.
    mutating func editFile(_ editableString: String, temporaryFileName: String?) throws -> String? {
        let fileName = temporaryFileName ?? "tmp.txt"
        let fileNameURL = URL(filePath: fileName, relativeTo: nil)

        let tempDir = try url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: fileNameURL,
            create: true
        )

        let tempFile = URL(filePath: fileNameURL.path(), relativeTo: tempDir)
        let tempFilePath = tempFile.absoluteURL.path()

        let editableStringData = editableString.data(using: .utf8)
        _ = createFile(atPath: tempFilePath, contents: editableStringData)

        try LHC.spawnAndWait(
            executableURL: URL(filePath: LHC.editor, directoryHint: .notDirectory),
            arguments: [tempFilePath]
        )

        guard let contents = contents(atPath: tempFilePath),
              let string = String(data: contents, encoding: .utf8) else { return nil }

        return string
    }
}

extension FileManagerish {
    func traverseUpwardsUntilFinding(fileName: String, startingPoint: String? = nil, isDirectory: Bool? = false) -> String? {
        var url: URL
        if let startingPoint {
            url = URL(filePath: startingPoint)
        } else {
            url = URL(filePath: currentDirectoryPath, directoryHint: .isDirectory)
        }
        url = url.appending(path: fileName)

        var thisIsDir: Bool?
        while !fileExists(atPath: url.path(), isDirectory: &thisIsDir) ||
                (isDirectory != nil && isDirectory != thisIsDir) {
            url = url.deletingLastPathComponent()

            guard url.path() != "/" &&
                    (try? url.canonicalPath) != "/" else {
                return nil
            }

            let directoryHint: URL.DirectoryHint
            switch isDirectory {
            case true:
                directoryHint = .isDirectory
            case false:
                directoryHint = .notDirectory
            default: // (nil)
                directoryHint = .notDirectory
            }
            url = url
                .appending(component: "../", directoryHint: .inferFromPath)
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

extension LHC {
    static var fileManager: FileManagerish = FileManager.default

    static var isInteractiveSession: (() -> Bool) = { isatty(STDOUT_FILENO) == 1 }
}
