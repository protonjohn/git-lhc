//
//  Check.swift
//  
//
//  Created by John Biggs on 11.12.23.
//

import Foundation
import ArgumentParser
import LHC
import LHCInternal
import SwiftGit2
import Version
import Stencil

struct Check: AsyncParsableCommand {
    @OptionGroup()
    var parent: LHC.Options

    @Flag(
        name: .shortAndLong
    )
    var dryRun: Bool = false

    @Flag()
    var last: Bool = false

    @Flag(
        name: .short
    )
    var nonInteractive: Bool = false

    @Argument()
    var checklist: String

    @Argument()
    var reference: String?

    @MainActor
    mutating func run() async throws {
        Internal.initialize()

        parent.commandConfigDefines = [
            "checklist": checklist
        ]

        var repo = try Internal.openRepo(at: parent.repo)

        let options = try? parent.options?.get()
        guard var checklistDir = options?.checklistDir else {
            throw ValidationError("No checklist directory configured.")
        }

        while checklistDir.hasSuffix("/") {
            checklistDir.removeLast()
        }

        let checklistsURL = URL(filePath: parent.repo).appending(path: checklistDir)

        let refRoot = options?.checklistRefRootWithTrailingSlash ?? "refs/notes/checklists"
        let checklistRef = refRoot.appending(checklist)

        // Figure out what the checklist is being run for, and warn the user if it happens to be a tag.
        let tip = try getTipAndWarnUser(repo: repo)

        // Render the checklist template according to the settings and the commit/tag history.
        let environment = Stencil.Environment(
            repository: repo,
            options: options,
            urls: [checklistsURL, checklistsURL.appending(path: "templates")]
        )
        var context: [String: Any] = [:]
        if let evaluatedConfig = try parent.evaluatedConfig?.get() {
            context["config"] = evaluatedConfig
        }

        let checklist = try environment.renderChecklist(named: checklist, for: tip, context: context)

        // Evaluate the checklist and get the logs from its invocation.
        let log = try await evaluate(checklist)

        // If this is just a dry run, we don't actually care about formatting & attaching the log, just return.
        guard !dryRun else {
            return
        }

        let result = log.format()

        let signingOptions = try parent.signingOptions()
        let defaultSignature = try repo.defaultSignature
        
        _ = try repo.createNote(
            for: tip,
            message: result,
            author: defaultSignature,
            committer: defaultSignature,
            noteCommitMessage: "Checklist \(self.checklist) evaluated by 'git-lhc check'",
            notesRefName: checklistRef,
            force: false
        ) {
            guard let signingOptions else {
                return nil
            }

            return try LHC.sign($0, options: signingOptions)
        }
    }

    mutating func evaluate(_ checklist: Checklist) async throws -> Checklist.Log {
        let yesNo: InteractiveOptions = [.yes.asDefault, .no]
        var previousResult: Data?

        let nonInteractive = self.nonInteractive
        let log = await checklist.evaluate { step, behavior, index, command, log in
            let options = behavior.options(with: [.edit])
            let optionString = options.optionString

            let language = command?.language
            if let command = command?.0,
               language != "txt",
               case var command = String(command) {
                if let language {
                    let endIndex = command.index(command.endIndex, offsetBy: -3)
                    command = String(command.trimmingPrefix("```\(language)")[..<endIndex])
                } else {
                    command = command.trimmingCharacters(
                        in: .whitespacesAndNewlines.union(.init(charactersIn: "`"))
                    )
                }

                if command.contains("\n") { // Multiline
                    guard let result = try log.promptEditingFile(
                        initialValue: command,
                        options: options,
                        nonInteractive: nonInteractive,
                        prompt: { _ in
                            "Will run the command in the block above. Continue? (\(optionString)) "
                        }
                    ) else {
                        throw CheckError.userAborted
                    }

                    command = result
                } else { // Single line (could be block or inline)
                    guard let result = log.promptReadingLine(
                        initialValue: command,
                        options: options,
                        nonInteractive: nonInteractive,
                        prompt: { value in
                            "Will run `\(value)`. Continue? (\(optionString)) "
                        }, edit: { _ in
                            "Enter command: "
                        }
                    ) else {
                        throw CheckError.userAborted
                    }

                    command = result
                }

                previousResult = try await log.logCommand(
                    command,
                    language: language,
                    previousResult: previousResult
                )
            }

            var notes = ""
            if !nonInteractive,
               log.promptLoop(
                initialValue: "",
                options: yesNo,
                continueCallback: { [weak log] value in
                    log?.prompt(
                        "Step \(index) complete. Add notes? (\(yesNo.optionString)) ",
                        nonInteractive: nonInteractive,
                        onNewLine: true
                    ) ?? ""
                }, editCallback: nil
            ) != nil {
                log.log(.checkPrompt, "Enter your notes below, followed by an empty line:\n")
                while case let line = log.prompt("> ", nonInteractive: false), !line.isEmpty {
                    notes += "> \(line)"
                }
            }

            // We don't care about the actual value here, because it's being written to the log as the user types.
            guard try log.promptEditingFile(
                initialValue: notes,
                options: options,
                nonInteractive: nonInteractive,
                fileExtension: "md",
                prompt: { promptNotes in
                    if promptNotes.isEmpty {
                        return "Continue checklist without notes? You can also press 'e' to edit. (\(optionString)) "
                    } else if promptNotes != notes {
                        return "\(promptNotes)Continue with the notes above? (\(optionString)) "
                    } else {
                        return "Continue checklist with the above notes? You can also press 'e' to edit. (\(optionString)) "
                    }
                }
            ) != nil else {
                throw CheckError.userAborted
            }
        }

        return log
    }

    mutating func getTipAndWarnUser(repo: Repositoryish) throws -> ObjectID {
        var tip: ObjectID?
        if let reference {
            let parsedObject = try repo.object(parsing: reference)
            if let tag = parsedObject as? Tagish {
                tip = tag.target.oid
            } else {
                tip = parsedObject.oid
            }
        } else {
            var unwarnedTags: [String] = []

            let head = try repo.HEAD()
            if let tags = try repo.tagsByTarget()[head.oid] {
                if let options = try? parent.allTrainOptions() {
                    for (_, option) in options {
                        for tag in tags {
                            var wasWarned = false
                            defer {
                                if !wasWarned {
                                    unwarnedTags.append(tag.name)
                                }
                            }

                            guard let version = Version(prefix: option.tagPrefix, versionString: tag.name) else {
                                continue
                            }

                            if let release = try? repo.release(exactVersion: version, options: option) {
                                let train = release.train != nil ? "\(release.train!) " : ""
                                guard Internal.promptForConfirmation("""
                                    Warning: you are running this checklist on commit \(head.oid), but the \
                                    \(train) release tag for version \(release.versionString) also points to the same \
                                    object. If you want to explicitly attach a checklist to a release, you must do so \
                                    by specifying the reference name, for example, `git-lhc check example 1.2.3`.

                                    Continue attaching the checklist to this commit?
                                    """, continueText: false) else {
                                    throw CheckError.userAborted
                                }

                                wasWarned = true
                            }
                        }
                    }
                } else {
                    for tag in tags {
                        var wasWarned = false
                        defer {
                            if !wasWarned {
                                unwarnedTags.append(tag.name)
                            }
                        }

                        guard let version = Version(tag.name) else {
                            continue
                        }

                        guard Internal.promptForConfirmation("""
                            Warning: you are running this checklist on commit \(head.oid), but the \
                            release tag for version \(version) also points to the same object. \
                            If you want to explicitly attach a checklist to a release, you must do so \
                            by specifying the reference name, for example, `git-lhc check example 1.2.3`.

                            Continue attaching the checklist to this commit?
                            """, continueText: false) else {
                            throw CheckError.userAborted
                        }

                        wasWarned = true
                    }
                }
            }

            if !unwarnedTags.isEmpty {
                if unwarnedTags.count == 1 {
                    Internal.print("""
                        Warning: attaching checklist to commit \(head.oid) instead of \(unwarnedTags.first!)
                        """, error: true)
                } else {
                    Internal.print("""
                        Warning: attaching checklist to commit \(head.oid) instead of one of these tags, which point to \
                        the same object: \(unwarnedTags.humanReadableDelineatedString)
                        """, error: true)
                }
            }

            tip = head.oid
        }

        return tip!
    }

}

extension Checklist.Log {
    func promptLoop(
        initialValue: String,
        options: InteractiveOptions,
        continueCallback: @escaping ((String) throws -> String),
        editCallback: ((String) throws -> String)?
    ) rethrows -> String? {
        var value = initialValue

        // Put the prompt log output inside a code block
        log(.noEcho, "```", onNewLine: true)
        defer {
            log(.noEcho, "```\n", onNewLine: true)
        }

        while true {
            var option: InteractiveOption?
            while true {
                let response = try continueCallback(value).trimmingCharacters(in: .whitespacesAndNewlines)
                guard let choice = options.chosenOption(from: response), options.contains(choice) else {
                    log(.checkError, "Unrecognized choice '\(response)'.")
                    continue
                }
                option = choice
                break
            }

            guard let option else {
                fatalError("Unrecognized option.")
            }

            switch option {
            case .yes:
                return value
            case .no:
                return nil
            case .edit:
                value = try editCallback!(value)
            case .help:
                log(.checkPrompt, options.help)
            default:
                fatalError("Unrecognized option: \(option)")
            }
        }
    }

    func promptEditingFile(
        initialValue value: String,
        options: InteractiveOptions,
        nonInteractive: Bool,
        fileExtension: String? = nil,
        prompt promptClosure: @escaping ((String) -> String)
    ) throws -> String? {
        return try promptLoop(
            initialValue: value,
            options: options
        ) { [unowned self] value in
            let promptString = promptClosure(value)
            return prompt(promptString, nonInteractive: nonInteractive, onNewLine: true)
        } editCallback: { value in
            let tmpFile = "lhc.check.\(Internal.processInfo.processIdentifier).\(fileExtension ?? "txt")"
            return try Internal.fileManager.editFile(value, temporaryFileName: tmpFile) ?? ""
        }
    }

    func promptReadingLine(
        initialValue value: String,
        options: InteractiveOptions,
        nonInteractive: Bool,
        prompt promptClosure: @escaping ((String) -> String),
        edit editClosure: @escaping ((String) -> String)
    ) -> String? {
        return promptLoop(
            initialValue: value,
            options: options
        ) { [unowned self] value in
            let promptString = promptClosure(value)
            return prompt(promptString, nonInteractive: nonInteractive, onNewLine: true)
        } editCallback: { [unowned self] value in
            let promptString = editClosure(value)
            return prompt(promptString, nonInteractive: nonInteractive, onNewLine: true)
        }
    }

    func logCommand(_ command: String, language: String?, previousResult: Data?) async throws -> Data? {
        var environment = Internal.processInfo.environment
        if let previousResult, let string = String(data: previousResult, encoding: .utf8) {
            environment[LHCEnvironment.previousChecklistResult.key] = string
        }

        var output = Data()
        var exitCode: Int32 = 0
        var isInteractive = false

        var printed = false

        // Command output should stay inside a code block.
        defer {
            if printed {
                log(.noEcho, "```\n", onNewLine: true)
            }
        }

        var shebang: String? = nil
        if let language {
            shebang = "/usr/bin/env \(language)"
        }

        for await item in try Internal.shell.run(
            shebang: shebang,
            command: command,
            environment: environment
        ) {
            var line: Data?
            var kind: Checklist.LogItem.Kind?

            switch item {
            case .success(let result):
                switch result {
                case .pid:
                    continue
                case .termio:
                    if !isInteractive {
                        isInteractive = true
                        line = "[...]".data(using: .utf8)
                        kind = .commandStdout
                    }
                    continue
                case .stdin(let data):
                    line = data
                    kind = .userInput
                case .stdout(let data):
                    guard let data else { break }
                    line = data
                    output += data
                    kind = .commandStdout
                case .stderr(let data):
                    guard let data else { break }
                    line = data
                    kind = .commandStderr
                case .exit(let result):
                    exitCode = result
                }
            case .failure(let error):
                throw error
            }

            if let line,
               let kind,
               var string = String(data: line, encoding: .utf8),
               !isInteractive {
                if !printed {
                    printed = true
                    log(.noEcho, "```\n", onNewLine: true)
                }

                if string.contains(.ansiEscape) {
                    isInteractive = true
                    string = "[...]"
                }

                log(kind, string)
            }
        }

        guard exitCode == 0 else {
            throw ExitCode(exitCode)
        }

        return output
    }
}

struct ChecklistCommandError: Error, CustomStringConvertible {
    let command: String
    let errorOutput: String?
    let exitCode: Int

    var description: String {
        var result = "The command `\(command)` exited with code \(exitCode)."
        if let errorOutput {
            // Note the extra space to allow for the period above
            result += """
                 It included the following error output:
                ```
                \(errorOutput)
                ```
                """
        }
        return result
    }
}

enum CheckError: String, Error, CustomStringConvertible {
    case checklistNotFound = "No checklist was found with that name."
    case tooManyCommands = "No more than one command can be specified per checklist item."
    case userAborted = "User aborted."

    var description: String {
        rawValue
    }
}
