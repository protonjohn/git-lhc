//
//  Interaction.swift
//  
//
//  Created by John Biggs on 13.10.23.
//

import Foundation

public protocol Printer {
    mutating func print(_ item: String, error: Bool)
}

public struct SwiftPrinter: Printer {
    public func print(_ item: String, error: Bool) {
        var output: TextOutputStream = error ? FileHandle.standardError : FileHandle.standardOutput
        Swift.print(item, separator: "", terminator: "", to: &output)
    }
}

extension Internal {
    public internal(set) static var printer: Printer = SwiftPrinter()

    public static func print(_ items: Any..., separator: String = " ", terminator: String = "\n", error: Bool = false) {
        printer.print(
            items.map { String(describing: $0) }.joined(separator: separator) + terminator,
            error: error
        )
    }
}

public protocol VerboseCommand {
    var verbose: Bool { get }
}

extension VerboseCommand {
    public func printIfVerbose(_ items: Any..., separator: String = " ", terminator: String = "\n", error: Bool = false) {
        guard verbose else { return }
        
        Internal.printer.print(
            items.map { String(describing: $0) }.joined(separator: separator) + terminator,
            error: error
        )
    }
}

extension Internal {
    public internal(set) static var readPassphrase: ((String) -> String?) = { prompt in
        var buf = [CChar](repeating: 0, count: 8192)
        guard let passphraseBytes = readpassphrase(prompt, &buf, buf.count, 0) else {
            return nil
        }
        return String(cString: passphraseBytes)
    }

    public internal(set) static var promptUser: ((String) -> String?) = {
        Self.print($0, terminator: "")
        return readLine(strippingNewline: true)
    }

    public static func promptForPassword(_ prompt: String = "Enter passphrase: ") -> String? {
        readPassphrase(prompt)
    }

    public static func promptForConfirmation(_ prompt: String, continueText: Bool = true, defaultAction: Bool = true) -> Bool {
        let action = defaultAction ? "Y/n" : "y/N"
        var prompt = "\(prompt) \(continueText ? "Continue? " : "")(\(action)) "

        repeat {
            guard let string = Self.promptUser(prompt) else {
                Internal.print("Encountered unexpected EOF.")
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

public protocol QuietCommand {
    var quiet: Bool { get }
}

extension QuietCommand {
    public func readPassphraseIfNotQuiet() -> String? {
        guard !quiet else { return "" }

        return Internal.promptForPassword()
    }

    public func promptForConfirmationIfNotQuiet(_ prompt: String, continueText: Bool = true, defaultAction: Bool = true) -> Bool {
        guard !quiet else { return true }

        return Internal.promptForConfirmation(prompt, continueText: continueText, defaultAction: defaultAction)
    }
}

extension Internal {
    public internal(set) static var spawnProcessAndWaitForTermination: ((URL, [String]) throws -> ()) = { url, arguments in
        let task = Process()
        task.executableURL = url
        task.arguments = arguments
        task.environment = Internal.processInfo.environment

        task.standardInput = FileHandle(forReadingAtPath: "/dev/tty")
        task.standardError = FileHandle(forWritingAtPath: "/dev/tty")
        task.standardOutput = FileHandle(forWritingAtPath: "/dev/tty")

        try task.run()
        // Note: this is pure wizardry but is absolutely key to making spawn work properly
        tcsetpgrp(STDIN_FILENO, task.processIdentifier)

        task.waitUntilExit()
    }

    public static func spawnAndWait(executableURL: URL, arguments: [String]) throws {
        try spawnProcessAndWaitForTermination(executableURL, arguments)
    }
}
