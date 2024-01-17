//
//  Extensions.swift
//  
//
//  Created by John Biggs on 29.11.23.
//

import Foundation

extension ObjectID {
    /* OIDs are represented as hexadecimal strings. */
    static let stringLength = MemoryLayout<RawValue>.size * 2
}

extension Collection {
    public subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }

    public var second: Element? {
        guard count > 1 else { return nil }
        return self[index(after: startIndex)]
    }
}

extension Array<String> {
    public var humanReadableDelineatedString: String {
        guard count != 1 else { return first! }

        let secondToLastIndex = index(before: endIndex)
        guard secondToLastIndex > startIndex, let last else { return "" }
        return self[startIndex..<secondToLastIndex].joined(separator: ", ") + ", and \(last)"
    }
}

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
    public static let ansiEscape: Self = "\u{001B}["

    public func indented(times: Int = 1, prefix: String = "    ") -> String {
        let lines = components(separatedBy: "\n")
        return lines
            .map { String(repeating: prefix, count: times) + $0 }
            .joined(separator: "\n")
    }

    public func isAll(inSet set: CharacterSet) -> Bool {
        return unicodeScalars.allSatisfy { set.contains($0) }
    }

    public var couldBeJSON: Bool {
        return first == "[" && last == "]" ||
            first == "{" && last == "}"
    }
}

extension Int {
    public static func percent(_ numerator: Int, _ denominator: Int) -> Self {
        Int(Double(numerator) / Double(denominator) * 100)
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

extension TimeInterval {
    private static let dateComponentsFormatter = DateComponentsFormatter()

    public static func milliseconds(_ milliseconds: Int) -> Self {
        Self(milliseconds) / 1000
    }

    public static func minutes(_ minutes: Int) -> Self {
        Self(minutes) * 60
    }

    public static func hours(_ hours: Int) -> Self {
        Self(hours) * .minutes(60)
    }

    public static func days(_ days: Int) -> Self {
        Self(days) * .hours(24)
    }

    public static func weeks(_ weeks: Int) -> Self {
        Self(weeks) * .days(7)
    }

    public var formattedString: String? {
        guard let value = Self.dateComponentsFormatter.string(from: self) else {
            return nil
        }

        if value.isAll(inSet: .decimalDigits) {
            return "\(value)s"
        }

        return value
    }

    public init?(string: String) {
        let scanner = Scanner(string: string)

        var weeks: Int?
        var days: Int?
        var hours: Int?
        var minutes: Int?
        var seconds: Int?

        let markers = CharacterSet(charactersIn: "wdhm")

        while let substring = scanner.scanCharacters(from: .decimalDigits),
              let int = Int(substring) {
            switch scanner.scanCharacters(from: markers) {
            case "w":
                guard weeks == nil && days == nil && hours == nil && minutes == nil else {
                    return nil
                }
                weeks = int
            case "d":
                guard days == nil && hours == nil && minutes == nil else {
                    return nil
                }
                days = int
            case "h":
                guard hours == nil && minutes == nil else {
                    return nil
                }
                hours = int
            case "m":
                guard minutes == nil else {
                    return nil
                }
                minutes = int
            default:
                guard scanner.isAtEnd else {
                    return nil
                }
                seconds = int
            }
        }

        var total: Self = 0
        if let weeks {
            total += .weeks(weeks)
        }
        if let days {
            total += .days(days)
        }
        if let hours {
            total += .hours(hours)
        }
        if let minutes {
            total += .minutes(minutes)
        }
        if let seconds {
            total += Self(seconds)
        }

        self = total
    }
}


extension POSIXError {
    static var global: Self {
        .init(.init(rawValue: errno) ?? .ELAST)
    }
}
