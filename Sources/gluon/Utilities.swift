//
//  Utilities.swift
//  
//
//  Created by John Biggs on 10.10.23.
//

import Foundation
import ArgumentParser

extension Substring {
    func advanced(by n: Int) -> Self {
        let start = (0..<n)
            .reduce(into: startIndex) { result, _ in
                result = self.index(after: result)
            }
        return self[start...]
    }
}

extension URL {
    var canonicalPath: String? {
        get throws {
            try resourceValues(forKeys: [.canonicalPathKey]).canonicalPath
        }
    }

    static func createFromPathOrThrow(_ path: String) throws -> Self {
        guard let url = Self(string: path) else {
            throw GluonError.invalidPath(path)
        }
        return url
    }
}

extension FileHandle: TextOutputStream {
    public func write(_ string: String) {
        try? write(contentsOf: string.data(using: .utf8) ?? Data())
    }
}

extension RandomAccessCollection {
    /// - Warning: The collection *must* be sorted according to the predicate.
    func binarySearch(predicate: (Iterator.Element) -> Bool) -> Index {
        var low = startIndex
        var high = endIndex
        while low != high {
            let mid = index(low, offsetBy: distance(from: low, to: high) / 2)
            if predicate(self[mid]) {
                low = index(after: mid)
            } else {
                high = mid
            }
        }
        return low
    }
}

extension Bool {
    init?(promptString: String) {
        let promptString = promptString.lowercased()

        if promptString == "yes" || promptString == "y" {
            self = true
        } else if promptString == "no" || promptString == "n" {
            self = false
        } else {
            return nil
        }
    }
}

extension String {
    func indented(times: Int = 1, prefix: String = "    ") -> String {
        let lines = components(separatedBy: "\n")
        return lines
            .map { String(repeating: prefix, count: times) + $0 }
            .joined(separator: "\n")
    }
}

extension ExpressibleByArgument where Self: CaseIterable & RawRepresentable, RawValue == String {
    static var possibleValues: String { allCases.map(\.rawValue).joined(separator: ", ") }
}
