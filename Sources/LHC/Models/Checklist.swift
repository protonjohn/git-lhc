//
//  Checklist.swift
//  
//
//  Created by John Biggs on 12.12.23.
//

import Foundation
import LHCInternal
import Markdown
import Stencil
import SwiftGit2

public struct Checklist {
    public struct Step {
        /// The range in the original document of the step.
        public let range: SourceRange

        public let language: String?

        /// The item to run as part of the step.
        ///
        /// This can be a code block, or an inline code element.
        ///
        /// Any code block occurring after a list item, and any text between it, will be considered as part of
        /// that list item. Any inline code must stay inside the list item.
        public let commandRange: SourceRange?
    }

    public enum Default: Character {
        case no = "-"
        case yes = "+"
        case neither = "*"

        public init?(_ substring: Substring) {
            guard let first = substring.trimmingCharacters(in: .whitespaces).first else { return nil }
            guard let result = Self(rawValue: first) else { return nil }
            self = result
        }

        public func options(with extras: [InteractiveOption] = []) -> InteractiveOptions {
            let result: InteractiveOptions = extras + [.help]
            switch self {
            case .no:
                return [.yes, .no.asDefault] + result
            case .yes:
                return [.yes.asDefault, .no] + result
            case .neither:
                return [.yes, .no] + result
            }
        }
    }

    struct Reader: MarkupWalker {
        enum CommandItem: Equatable {
            case block(language: String?)
            case inline

            var isBlock: Bool {
                guard case .block = self else { return false }
                return true
            }
        }

        var checkItems: [SourceRange] = []
        var commandItems: [(item: CommandItem, range: SourceRange)] = []

        var steps: [Step] {
            get throws {
                // We want the first check items to be at the end of the list.
                var stack = commandItems.sorted {
                    let (lhs, rhs) = ($0.range, $1.range)
                    return Self.isBefore(rhs, lhs) // sorted in reverse order for stack functions
                }
                let checkItems = checkItems.sorted(by: Self.isBefore)

                var result: [Step] = []
                for (i, checklistItemRange) in checkItems.enumerated() {
                    var checklistItemRange = checklistItemRange
                    // Make sure there are no overlapping ranges between the list items.
                    // For example, if a list item has sublists, make sure its end range is clipped to the
                    // beginning of the first subentry.
                    var theseCommandItems: [SourceRange] = []
                    let nextBound = checkItems[safe: i + 1]?.lowerBound
                    if let nextBound, nextBound < checklistItemRange.upperBound {
                        checklistItemRange = checklistItemRange.lowerBound..<nextBound
                    }

                    // Where we should look for commands in the current list item. It goes as far as to the start of
                    // the next list item, if it exists, or the end of the current list item.
                    let commandItemsBound = nextBound ?? checklistItemRange.upperBound

                    // If we're at the end of the list, we want to make sure to capture any command blocks after the
                    // very last element.
                    var language: String?
                    while let bound = stack.last?.range.lowerBound,
                          bound < commandItemsBound || i == checkItems.endIndex - 1,
                          let last = stack.popLast() {
                        guard last.item.isBlock || checklistItemRange.clamped(to: last.range) == last.range else {
                            throw ChecklistError(
                                reason: .inlineNeedsToBePartOfListItem,
                                location: last.range.lowerBound
                            )
                        }

                        if checklistItemRange.upperBound < last.range.upperBound {
                            checklistItemRange = checklistItemRange.lowerBound..<last.range.upperBound
                        }
                        theseCommandItems.append(last.range)
                        if case let .block(commandLanguage) = last.item {
                            language = commandLanguage
                        }
                    }

                    guard theseCommandItems.count <= 1 else {
                        throw ChecklistError(
                            reason: .moreThanOneCommandPerStep,
                            location: checkItems.second!.lowerBound
                        )
                    }

                    result.append(.init(
                        range: checklistItemRange,
                        language: language,
                        commandRange: theseCommandItems.first
                    ))
                }

                return result
            }
        }

        mutating func defaultVisit(_ markup: Markup) {
            descendInto(markup)
        }

        mutating func visitListItem(_ listItem: ListItem) {
            // We only consider values that are part of the original source.
            guard let range = listItem.range else {
                return
            }

            checkItems.append(range)
            descendInto(listItem)
        }

        mutating func visitInlineCode(_ inlineCode: InlineCode) {
            guard let range = inlineCode.range else {
                return
            }

            descendInto(inlineCode)
            commandItems.append((.inline, range))
        }

        mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> () {
            guard let range = codeBlock.range else {
                return
            }

            descendInto(codeBlock)
            commandItems.append((.block(language: codeBlock.language), range))
        }

        static func steps(of markdown: Document) throws -> [Step] {
            var reader = Self()
            reader.visit(markdown)
            return try reader.steps
        }

        static func isBefore(_ lhs: SourceRange?, _ rhs: SourceRange?) -> Bool {
            guard let lhs else { return false }
            guard let rhs else { return true }
            return lhs.lowerBound < rhs.lowerBound
        }
    }

    public struct LogItem: Codable {
        static let dateFormatter: DateFormatter = {
            let result = DateFormatter()
            result.dateFormat = "HH:MM:ss"
            return result
        }()

        public enum Kind: String, Codable {
            /// An excerpt of the original checklist document.
            case excerpt
            /// Standard output contents of a command contained in the checklist.
            case commandStdout
            /// Standard error contents of a command contained in the checklist.
            case commandStderr
            /// Notes from a user for a given step.
            case userNotes
            /// User input for something that isn't a note.
            case userInput
            /// A prompt coming from the check program itself.
            case checkPrompt
            /// Information placed in the log directly by the check command.
            case checkLog
            /// An error message coming from the check program itself.
            case checkError
            /// Doesn't get printed, but gets recorded to the log. Used for adding markdown formatting without
            /// cluttering up the terminal session.
            case noEcho

            /// Whether the log item should appear with a date in the evaluated result.
            var hasDate: Bool {
                switch self {
                case .excerpt, .userNotes, .noEcho:
                    return false
                default:
                    return true
                }
            }

            /// Whether the log item represents error output.
            var isError: Bool {
                switch self {
                case .commandStderr, .checkError:
                    return true
                default:
                    return false
                }
            }

            /// Whether check should print the given item to the console.
            var shouldPrint: Bool {
                switch self {
                case .userNotes, .userInput, .commandStderr, .commandStdout, .noEcho:
                    return false
                default:
                    return true
                }
            }
        }

        /// The timestamp for the entry in question.
        public let date: Date?
        /// The content type.
        public let kind: Kind
        /// The log content.
        public let string: String

        public init(_ kind: Kind, _ string: String) {
            self.date = kind.hasDate ? Date() : nil
            self.kind = kind
            self.string = string
        }
    }

    public final class Log {
        public typealias PrintCallback = (String, Bool) -> ()

        let callback: PrintCallback
        public var items: [LogItem] = []
        public var failed: Bool = false

        func append(_ item: LogItem) {
            items.append(item)
        }

        public static let terminal: PrintCallback = {
            Internal.print($0, terminator: "", error: $1)
        }

        public init(callback: @escaping PrintCallback) {
            self.callback = callback
        }
    }

    public typealias StepCallback = ((Substring, Default, Int, (Substring, language: String?)?, inout Log) async throws -> ())

    /// The original string contents of the document.
    public let contents: String

    /// The steps contained in the markdown file.
    public let steps: [Step]

    /// `offsets[0]` is the `startIndex` of line 0, `offsets[1]` is the `startIndex` of line 1, etc.
    ///
    /// This list of indices helps us quickly calculate an index into the file based on row and column information.
    let offsets: [String.Index]

    public init(parsing string: String) throws {
        contents = string
        steps = try Reader.steps(of: Document(parsing: string))
        offsets = contents.split(separator: "\n", omittingEmptySubsequences: false).reduce(into: [], {
            guard let last = $0.last else {
                $0.append(string.index(after: $1.endIndex))
                return
            }

            let index = string.index(last, offsetBy: $1.count)
            if index == string.endIndex {
                $0.append(index)
            } else if $1.count == 0 || string[index] == "\n" {
                // Add 1 to account for the newline character.
                $0.append(string.index(after: index))
            }
        })
    }

    private func index(for location: SourceLocation) -> String.Index? {
        // Lines and columns are 1-indexed.
        let (rowIndex, colIndex) = (location.line - 1, location.column - 1)
        // Offset contains the end of the given line, so look at the previous entry.
        let rowOffset = rowIndex == 0 ? contents.startIndex : offsets[rowIndex - 1]

        return contents.index(rowOffset, offsetBy: colIndex)
    }

    private func trim(forwards: Bool = true, startingAt index: String.Index) -> String.Index {
        var index = index

        while contents[index].isWhitespace {
            index = forwards ? contents.index(after: index) : contents.index(before: index)
        }

        return index
    }

    private func start(of step: Step, trimmingWhitespace: Bool = false) -> String.Index {
        guard var index = index(for: step.range.lowerBound) else {
            fatalError("Invariant error: step \(step) should be original part of document.")
        }

        if trimmingWhitespace {
            index = trim(startingAt: index)
        }

        return index
    }

    private func end(of step: Step, trimmingWhitespace: Bool = false) -> String.Index {
        guard var index = index(for: step.range.upperBound) else {
            fatalError("Invariant error: step \(step) should be original part of document.")
        }

        if trimmingWhitespace {
            // Get a value inside the closed upper bound, since that's where the whitespace will be.
            let insideRange = contents.index(before: index)
            let newBound = trim(forwards: false, startingAt: insideRange)

            if newBound != insideRange {
                index = contents.index(after: newBound)
            }
        }

        return index
    }

    private func excerpt(for range: SourceRange, trimmingWhitespace: Bool = false) -> Substring? {
        guard let start = index(for: range.lowerBound), let end = index(for: range.upperBound) else {
            return nil
        }

        return contents[start..<end]
    }

    private func excerpt(for step: Step) -> Substring {
        guard let excerpt = excerpt(for: step.range, trimmingWhitespace: true) else {
            fatalError("Invariant error: step \(step) should be original part of document.")
        }
        return excerpt
    }

    public func evaluate(
        log: @escaping Log.PrintCallback = Log.terminal,
        stepCallback: @escaping StepCallback
    ) async -> Log {
        var last = contents.startIndex
        var log = Log(callback: log)
        var currentStep = 1

        for step in steps {
            // Print the document from our last position to the end of this step.
            let end = end(of: step, trimmingWhitespace: true)

            // If we're not on the first step, then the user has already hit the newline on the terminal to enter their
            // response. In that case, clip the newline from the document contents.
            if last != contents.startIndex && contents[last] == "\n" {
                last = contents.index(after: last)
            }
            log.log(.excerpt, String(contents[last..<end]))

            defer {
                currentStep += 1
                last = contents.index(after: end)
            }

            let start = start(of: step, trimmingWhitespace: true)
            let excerpt = contents[start..<end]
            let behavior = Default(excerpt) ?? .no

            let commandExcerpt = step.commandRange != nil ? self.excerpt(for: step.commandRange!) : nil
            do {
                try await stepCallback(
                    excerpt,
                    behavior,
                    currentStep,
                    commandExcerpt != nil ? (commandExcerpt!, step.language) : nil,
                    &log
                )
            } catch {
                log.log(.checkError, """
                    > Warning: Checklist aborted: \(String(describing: error)) (\(currentStep) of \(steps.count) \
                    performed\(log.durationString).)\n
                    """)
                log.failed = true
                return log
            }
        }

        if last < contents.endIndex {
            log.log(.excerpt, String(contents[last..<contents.endIndex]))
        }

        log.log(.checkLog, "> Checklist completed. (\(currentStep - 1) total steps performed\(log.durationString).)", onNewLine: true)

        return log
    }
}

public struct ChecklistError: Error, CustomStringConvertible {
    public enum Reason: String {
        case moreThanOneCommandPerStep = "Can't include more than one command in a checklist step."
        case inlineNeedsToBePartOfListItem = "Inline commands need to be part of a list item."
    }

    public let reason: Reason
    public let location: SourceLocation

    public var description: String {
        return "Error on line \(location.line), column \(location.column): \(reason.rawValue)"
    }

}

public extension Checklist.Log {
    private static let queue = DispatchQueue(label: "checklist log queue")
    typealias Bookmark = Array<Checklist.LogItem>.Index

    var durationSinceNow: TimeInterval? {
        guard let entry = items.first(where: { $0.date != nil }),
              let startDate = entry.date else { return nil }
        return -startDate.timeIntervalSinceNow
    }

    var durationString: String {
        guard let duration = durationSinceNow?.formattedString else {
            return ""
        }
        return " in \(duration)"
    }

    func log(_ kind: Checklist.LogItem.Kind, _ string: String, onNewLine newline: Bool = false) {
        Self.queue.async { [weak self] in
            var string = string
            if newline, self?.items.last?.string.hasSuffix("\n") == false {
                string = "\n" + string
            }

            let logEntry = Checklist.LogItem(kind, string)

            if kind.shouldPrint {
                self?.callback(string, kind.isError)
            }

            self?.append(logEntry)
        }
    }

    func prompt(
        _ prompt: String? = nil,
        nonInteractive: Bool,
        onNewLine newline: Bool = false
    ) -> String {
        if let prompt {
            log(.checkPrompt, prompt, onNewLine: newline)
        }

        let result: String

        guard !nonInteractive else {
            result = "y\n"
            log(.userInput, result)
            return result
        }

        result = Internal.promptUser(nil) ?? ""
        log(.userInput, result)

        return result
    }

    func bookmark() -> Bookmark {
        items.endIndex
    }

    func items(since: Bookmark) -> ArraySlice<Checklist.LogItem> {
        guard items.startIndex <= since && since <= items.endIndex else {
            return []
        }
        return items[since...]
    }

    func format() -> String {
        var result: String = ""

        for item in items {
            result += item.string
        }

        return result
    }
}

public extension Repositoryish {
    /// Return a list of reference names for which checklists exist, according to the provided options.
    /// If an oid is specified, the results are filtered to only include checklists evaluated for the given oid.
    ///
    /// - Note: this filters all references in the repository, so try not to call it unnecessarily.
    func checklistRefs(for oid: ObjectID? = nil, train: Trains.TrainImpl?) throws -> [String] {
        let refRoot = train?.checklistRefRootWithTrailingSlash ?? "refs/notes/checklists/"
        let refNames = try references(withPrefix: refRoot).map(\.longName)

        guard let oid else { return refNames }

        return refNames.filter {
            (try? note(for: oid, notesRef: $0)) != nil
        }
    }

    func checklistNames(fromRefNames refNames: [String], withNotesFor oid: ObjectID) -> [String] {
        refNames.filter {
            (try? note(for: oid, notesRef: $0)) != nil
        }.map {
            String($0.split(separator: "/").last!)
        }
    }
}

public extension Stencil.Environment {
    func renderChecklist(
        named checklist: String,
        for target: ObjectID,
        context: [String: Any]
    ) throws -> Checklist {
        guard var checklistDir = train?.checklistDirectory else {
            throw TemplateError.notFound
        }

        while checklistDir.hasSuffix("/") {
            checklistDir.removeLast()
        }

        var checklistRef = train?.checklistRefRootWithTrailingSlash ?? "refs/notes/checklists/"

        if !checklistRef.hasSuffix("/") {
            checklistRef.append("/")
        }
        checklistRef.append(checklist)

        var context = context
        context["object"] = target.description

        if let train {
            context["train"] = train
        }

        let commits: [Commitish]
        var lastObject: ObjectType?
        if let (object, lastNote) = try repository.lastNotedObject(from: target, notesRef: checklistRef) {
            context["lastNote"] = lastNote
            context["lastTarget"] = object
            lastObject = object

            var sinceOid = object.oid
            if let lastTag = lastObject as? Tagish {
                sinceOid = lastTag.target.oid
            }

            // warning: make sure this isn't including the commit that was last part of this checklist
            commits = try repository.commits(from: target, since: sinceOid)
        } else {
            commits = try repository.commits(from: target, since: nil)
        }
        context["commits"] = commits

        var oids: Set<ObjectID> = [target]
        oids.formUnion(commits.map(\.oid))
        if let lastObject {
            oids.insert(lastObject.oid)
        }

        context["oidStringLength"] = ObjectID.minimumLength(toLosslesslyRepresentStringsOf: oids, floor: 7)

        let changes: [ObjectID: ConventionalCommit] = commits.reduce(into: [:]) {
            var attributes: [ConventionalCommit.Trailer]?

            if let attrsRef = train?.attrsRef,
               let note = try? repository.note(for: $1.oid, notesRef: attrsRef) {
                attributes = note.attributes.trailers
            }

            if let change = try? ConventionalCommit(message: $1.message, attributes: attributes) {
                $0[$1.oid] = change
            }
        }
        context["changes"] = changes

        let commitOids: Set<ObjectID> = commits.reduce(into: []) { $0.insert($1.oid) }

        // Get all of the relevant releases, and filter by the ones falling in the determined commit range.
        let releases = try repository.allReleases(channel: nil, train: train).filter {
            var tagName = $0.versionString
            if let prefix = train?.tagPrefix {
                tagName = prefix + tagName
            }

            guard let tag = try? repository.tag(named: tagName), commitOids.contains(tag.oid) else {
                return false
            }
            return true
        }
        context["releases"] = releases

        let checklistName = "\(checklist).md"
        let contents = try renderTemplates(nameOrRoot: checklistName, additionalContext: context)
        guard contents.count == 1,
              let (name, result) = contents.first,
              name == checklistName,
              let result else {
            throw TemplateDoesNotExist(templateNames: [checklistName])
        }
        
        return try Checklist(parsing: result)
    }
}
