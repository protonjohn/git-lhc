//
//  Interaction.swift
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

protocol VerboseCommand {
    var verbose: Bool { get }
}

extension VerboseCommand {
    func printIfVerbose(_ items: Any..., separator: String = " ", terminator: String = "\n", error: Bool = false) {
        guard verbose else { return }
        
        Gluon.printer.print(
            items.map { String(describing: $0) }.joined(separator: separator) + terminator,
            error: error
        )
    }
}

extension Gluon {
    static var readPassphrase: (() -> String?) = {
        var buf = [CChar](repeating: 0, count: 8192)
        guard let passphraseBytes = readpassphrase("Enter passphrase: ", &buf, buf.count, 0) else {
            return nil
        }
        return String(cString: passphraseBytes)
    }

    static var promptUser: ((String) -> String?) = {
        Self.print($0, terminator: "")
        return readLine(strippingNewline: true)
    }

    static func promptForContinuation(_ prompt: String, defaultAction: Bool = true) -> Bool {
        let action = defaultAction ? "Y/n" : "y/N"
        var prompt = "\(prompt) Continue? (\(action)) "

        repeat {
            guard let string = Self.promptUser(prompt) else {
                Gluon.print("Encountered unexpected EOF.")
                return false
            }

            guard !string.isEmpty else {
                return defaultAction
            }

            guard let result = Bool(promptString: string) else {
                prompt = "Unknown response '\(string)'. Continue \(action): "
                continue
            }

            return result
        } while true
    }
}

protocol QuietCommand {
    var quiet: Bool { get }
}

extension QuietCommand {
    func readPassphraseIfNotQuiet() -> String? {
        guard !quiet else { return "" }

        return Gluon.readPassphrase()
    }

    func promptForContinuationIfNotQuiet(_ prompt: String, defaultAction: Bool = true) -> Bool {
        guard !quiet else { return true }

        return Gluon.promptForContinuation(prompt, defaultAction: defaultAction)
    }
}