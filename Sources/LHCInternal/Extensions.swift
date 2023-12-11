//
//  Utilities.swift
//  
//
//  Created by John Biggs on 29.11.23.
//

import Foundation

extension Substring {
    public func advanced(by n: Int) -> Self {
        let start = (0..<n)
            .reduce(into: startIndex) { result, _ in
                result = self.index(after: result)
            }
        return self[start...]
    }
}

extension String {
    public func indented(times: Int = 1, prefix: String = "    ") -> String {
        let lines = components(separatedBy: "\n")
        return lines
            .map { String(repeating: prefix, count: times) + $0 }
            .joined(separator: "\n")
    }

    public var couldBeJSON: Bool {
        return first == "[" && last == "]" ||
            first == "{" && last == "}"
    }
}

extension RandomAccessCollection {
    /// - Warning: The collection *must* be sorted according to the predicate.
    public func binarySearch(predicate: (Iterator.Element) -> Bool) -> Index {
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

extension FileHandle: TextOutputStream {
    public func write(_ string: String) {
        try? write(contentsOf: string.data(using: .utf8) ?? Data())
    }

    public static let ttyOut = FileHandle(forWritingAtPath: "/dev/tty")
    public static let ttyIn = FileHandle(forReadingAtPath: "/dev/tty")
}

extension Bool {
    public init?(promptString: String) {
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

extension CharacterSet {
    public func contains(character: Character) -> Bool {
        character.unicodeScalars.allSatisfy(contains(_:))
    }
}

extension Regex<AnyRegexOutput> {
    static var cache: [String: Self] = [:]

    /// Hack: compile a regex without throwing it away
    public init(caching string: String) throws {
        if let cachedItem = Self.cache[string] {
            self = cachedItem
            return
        }

        let regex = try Regex(string)
        Self.cache[string] = regex
        self = regex
    }
}
