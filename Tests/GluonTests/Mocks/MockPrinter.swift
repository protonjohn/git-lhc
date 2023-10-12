//
//  MockPrinter.swift
//  
//
//  Created by John Biggs on 13.10.23.
//

import Foundation
@testable import gluon

struct MockPrinter: Printer {
    var printedItems: [(String, stream: TextOutputStream?)]

    func line(_ items: Any..., separator: String, terminator: String) -> String {
        return items
            .map { String(describing: $0) }
            .joined(separator: separator) + terminator
    }

    mutating func print(_ items: Any..., separator: String, terminator: String) {
        printedItems.append((line(items, separator: separator, terminator: terminator), nil))
    }

    mutating func print(_ items: Any..., separator: String, terminator: String, to stream: inout TextOutputStream) {
        printedItems.append((line(items, separator: separator, terminator: terminator), stream))
    }

    static let mock: Self = .init(printedItems: [])
}
