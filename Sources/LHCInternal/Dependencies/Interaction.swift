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

/// Represents an error that occurs when an external program is invoked.
struct InvocationError: Error, CustomStringConvertible {
    let command: String
    let exitCode: Int32

    var description: String {
        return "Command '\(command)' exited with code \(exitCode)."
    }
}

extension Internal {
    public internal(set) static var spawnProcessAndWaitForTermination: ((
        URL,
        [String],
        [String: String],
        FileHandle?,
        FileHandle?,
        FileHandle?
    ) throws -> ()) = { url, arguments, environment, stdin, stdout, stderr in
        let task = Process()
        task.executableURL = url
        task.arguments = arguments
        task.environment = environment
        task.standardInput = stdin
        task.standardOutput = stdout
        task.standardError = stderr

        try task.run()
        // Note: this is pure wizardry but is absolutely key to making spawn work properly. It sets the
        // current terminal's associated process group ID equal to the child task, since `STDIN_FILENO` is
        // equal to the TTY in use if our STDIN isn't getting piped from somewhere.
        tcsetpgrp(STDIN_FILENO, task.processIdentifier)

        task.waitUntilExit()

        // Restore the previous value.
        tcsetpgrp(STDIN_FILENO, Internal.processInfo.processIdentifier)

        let status = task.terminationStatus
        guard status == 0 else {
            let command = "\(url.path()) \(arguments.joined(separator: " "))"
            throw InvocationError(command: command, exitCode: status)
        }
    }

    public static func spawnAndWait(
        executableURL: URL,
        arguments: [String],
        environment: [String: String] = Internal.processInfo.environment,
        standardInput: FileHandle? = .ttyIn,
        standardOutput: FileHandle? = .ttyOut,
        standardError: FileHandle? = .ttyOut
    ) throws {
        try spawnProcessAndWaitForTermination(
            executableURL,
            arguments,
            environment,
            standardInput,
            standardOutput,
            standardError
        )
    }

    public static func spawnAndWaitWithOutput(
        command: String,
        input: String?
    ) throws -> Data? {
        var inPipe: Pipe?
        if let input {
            inPipe = Pipe()
            DispatchQueue.global(qos: .default).async { [inPipe] in
                inPipe!.fileHandleForWriting.write(input)
                try? inPipe!.fileHandleForWriting.close()
            }
        }

        let output = Pipe()
        let shell = Internal.processInfo.environment["SHELL"] ?? "/bin/sh"

        try Internal.spawnAndWait(
            executableURL: URL(filePath: shell),
            arguments: [
                "-c",
                command
            ],
            standardInput: inPipe?.fileHandleForReading ?? .ttyIn,
            standardOutput: output.fileHandleForWriting
        )

        // Close the pipe so the read doesn't block
        try output.fileHandleForWriting.close()
        return try output.fileHandleForReading.readToEnd()
    }
}
