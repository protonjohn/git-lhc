//
//  Utilities.swift
//  
//
//  Created by John Biggs on 17.11.23.
//

import Foundation

public enum Either<Left: Hashable & Codable, Right: Hashable & Codable>: Hashable, Codable {
    case left(Left)
    case right(Right)

    public init(_ left: Left) {
        self = .left(left)
    }

    public init(_ right: Right) {
        self = .right(right)
    }

    public var left: Left? {
        guard case .left(let left) = self else {
            return nil
        }

        return left
    }

    public var right: Right? {
        guard case .right(let right) = self else {
            return nil
        }

        return right
    }
}

/// Useful for printing/writing to a file either a string or encoded data.
public typealias StringOrData = Either<String, Data>
extension StringOrData {
    public var data: Data? {
        switch self {
        case let .left(string):
            return string.data(using: .utf8)
        case let .right(data):
            return data
        }
    }

    /// - Warning: Only use this method for UTF-8 encoded data.
    public var string: String? {
        switch self {
        case let .left(string):
            return string
        case let .right(data):
            return String(data: data, encoding: .utf8)
        }
    }
}
