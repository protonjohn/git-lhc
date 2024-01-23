//
//  FileManager.swift
//  
//
//  Created by John Biggs on 10.10.23.
//

import Foundation

public protocol FileManagerish {
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

    mutating func createDirectory(atPath path: String, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey : Any]?) throws

    mutating func tempDir(appropriateFor: URL?) throws -> URL

    func canonicalPath(for url: URL) throws -> String?

    func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys: [URLResourceKey]?,
        options: FileManager.DirectoryEnumerationOptions
    ) throws -> [URL]
}

extension FileManagerish {
    public mutating func createFile(
        atPath path: String,
        contents data: Data?
    ) -> Bool {
        createFile(atPath: path, contents: data, attributes: nil)
    }

    public mutating func createDirectory(atPath path: String, withIntermediateDirectories createIntermediates: Bool = false) throws {
        try createDirectory(atPath: path, withIntermediateDirectories: createIntermediates, attributes: nil)
    }

    /// editFile: Spawn an editor session if detected to be running in a terminal.
    @available(*, noasync, message: "This function is not available from an async context.")
    public mutating func editFile(_ editableString: String, temporaryFileName: String? = nil) throws -> String? {
        let tempFilePath = try tempFile(contents: editableString.data(using: .utf8), fileName: temporaryFileName).path()

        let pointer: UnsafeMutablePointer<Result<Int32, Error>?> = .allocate(capacity: 1)
        pointer.initialize(to: nil)
        defer { pointer.deallocate() }

        let group = DispatchGroup()
        group.enter()
        Task.detached {
            do {
                for await event in try Internal.shell.run(
                    command: "\(Internal.editor) \(tempFilePath)"
                ) {
                    guard case .success(.exit(let code)) = event else { continue }

                    pointer.pointee = .success(code)
                    break
                }
            } catch {
                pointer.pointee = .failure(error)
            }
            group.leave()
        }

        group.wait()
        defer {
            try? removeItem(atPath: tempFilePath)
        }

        guard let result = pointer.pointee else {
            return nil
        }

        switch result {
        case .success(let exitCode):
            guard exitCode == 0,
                  let contents = contents(atPath: tempFilePath),
                  let string = String(data: contents, encoding: .utf8) else { return nil }
            return string
        case .failure(let error):
            throw error
        }
    }

    public mutating func tempFile(contents: Data?, fileName: String? = nil) throws -> URL {
        let tempDir = try tempDir(appropriateFor: nil)
        let fileName = URL(
            filePath: fileName ?? Internal.processInfo.globallyUniqueString,
            relativeTo: tempDir
        ).absoluteURL
        guard createFile(atPath: fileName.path(), contents: contents) else {
            throw FileError.couldntCreateFile(at: fileName.path())
        }

        return fileName
    }
}

public enum FileError: Error, CustomStringConvertible {
    case couldntCreateFile(at: String)

    public var description: String {
        switch self {
        case .couldntCreateFile(let path):
            return "Couldn't create file at \(path)."
        }
    }
}

extension FileManagerish {
    public func traverseUpwardsUntilFinding(fileName: String, startingPoint: String? = nil, isDirectory: Bool? = false) -> String? {
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
                    (try? canonicalPath(for: url)) != "/" else {
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
    public func fileExists(atPath path: String, isDirectory: inout Bool?) -> Bool {
        var isDir: ObjCBool = false

        let result = fileExists(atPath: path, isDirectory: &isDir)
        isDirectory = isDir.boolValue

        return result
    }

    public func tempDir(appropriateFor originalFile: URL?) throws -> URL {
        try url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: originalFile ?? self.temporaryDirectory,
            create: true
        )
    }

    public func canonicalPath(for url: URL) throws -> String? {
        try url.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath
    }
}

extension Internal {
    public static var fileManager: FileManagerish = FileManager.default

    public internal(set) static var isInteractiveSession: (() -> Bool) = { isatty(STDOUT_FILENO) == 1 }
}