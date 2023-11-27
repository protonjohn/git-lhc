//
//  Either.swift
//
//  Created by John Biggs on 13.10.23.
//

import Foundation

enum Either<Left, Right> {
    case left(Left)
    case right(Right)
}

/// Useful for printing/writing to a file either a string or encoded data.
typealias StringOrData = Either<String, Data>
extension StringOrData {
    var data: Data? {
        switch self {
        case let .left(string):
            return string.data(using: .utf8)
        case let .right(data):
            return data
        }
    }

    /// - Warning: Only use this method for UTF-8 encoded data.
    var string: String? {
        switch self {
        case let .left(string):
            return string
        case let .right(data):
            return String(data: data, encoding: .utf8)
        }
    }

    init(_ string: String) {
        self = .left(string)
    }

    init(_ data: Data) {
        self = .right(data)
    }
}
