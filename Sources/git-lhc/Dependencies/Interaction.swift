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

extension LHC {
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
        
        LHC.printer.print(
            items.map { String(describing: $0) }.joined(separator: separator) + terminator,
            error: error
        )
    }
}

extension LHC {
    static var readPassphrase: ((String) -> String?) = { prompt in
        var buf = [CChar](repeating: 0, count: 8192)
        guard let passphraseBytes = readpassphrase(prompt, &buf, buf.count, 0) else {
            return nil
        }
        return String(cString: passphraseBytes)
    }

    static var promptUser: ((String) -> String?) = {
        Self.print($0, terminator: "")
        return readLine(strippingNewline: true)
    }

    static func promptForPassword(_ prompt: String = "Enter passphrase: ") -> String? {
        readPassphrase(prompt)
    }

    static func promptForConfirmation(_ prompt: String, continueText: Bool = true, defaultAction: Bool = true) -> Bool {
        let action = defaultAction ? "Y/n" : "y/N"
        var prompt = "\(prompt) \(continueText ? "Continue? " : "")(\(action)) "

        repeat {
            guard let string = Self.promptUser(prompt) else {
                LHC.print("Encountered unexpected EOF.")
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

        return LHC.promptForPassword()
    }

    func promptForConfirmationIfNotQuiet(_ prompt: String, continueText: Bool = true, defaultAction: Bool = true) -> Bool {
        guard !quiet else { return true }

        return LHC.promptForConfirmation(prompt, continueText: continueText, defaultAction: defaultAction)
    }
}
