//
//  File.swift
//  
//
//  Created by John Biggs on 13.10.23.
//

import Foundation

protocol Printer {
    mutating func print(_ items: Any..., separator: String, terminator: String)
    mutating func print(_ items: Any..., separator: String, terminator: String, to stream: inout TextOutputStream)
}

struct SwiftPrinter: Printer {
    func print(_ items: Any..., separator: String, terminator: String) {
        Swift.print(items, separator: separator, terminator: terminator)
    }

    func print(_ items: Any..., separator: String, terminator: String, to stream: inout TextOutputStream) {
        Swift.print(items, separator: separator, terminator: terminator, to: &stream)
    }

    static let `default`: Self = .init()
}

extension Gluon {
    static var printer: Printer = SwiftPrinter.default

    static func print(_ items: Any..., separator: String = " ", terminator: String = "\n", to stream: inout TextOutputStream) {
        printer.print(items, separator: separator, terminator: terminator, to: &stream)
    }

    static func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
        printer.print(items, separator: separator, terminator: terminator)
    }
}
