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

extension FileManager: FileManagerish {
}

extension Gluon {
    static var fileManager: FileManagerish = FileManager.default
}
