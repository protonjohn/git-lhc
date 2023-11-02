//
//  File.swift
//  
//
//  Created by John Biggs on 13.10.23.
//

import Foundation

protocol Printer {
    mutating func print(_ item: String, error: Bool)
}

struct SwiftPrinter: Printer {
    func print(_ item: String, error: Bool) {
        var output: TextOutputStream = error ? FileHandle.standardError : FileHandle.standardOutput
        Swift.print(item, separator: "", terminator: "", to: &output)
    }
}

extension Gluon {
    static var printer: Printer = SwiftPrinter()

    static func print(_ items: Any..., separator: String = " ", terminator: String = "\n", error: Bool = false) {
        printer.print(
            items.map { String(describing: $0) }.joined(separator: separator) + terminator,
            error: error
        )
    }
}
