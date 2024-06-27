//
//  Attr.swift
//  
//
//  Created by John Biggs on 07.12.23.
//

import Foundation
import ArgumentParser
import LHC
import LHCInternal
import SwiftGit2

struct Attr: ParsableCommand {
    static var configuration = CommandConfiguration(subcommands: [
        Get.self, Add.self, Remove.self, Find.self, Log.self
    ])

    struct Get: ParsableCommand {
        @OptionGroup()
        var parent: LHC.Options

        @Flag(
            name: .shortAndLong
        )
        var verbose: Bool = false

        @Argument()
        var key: String

        @Argument()
        var revision: String?

        mutating func run() throws {
            Internal.initialize()
            let repo = try Internal.openRepo(at: parent.repo)

            let target: ObjectID
            if let revision {
                target = try repo.object(parsing: revision).oid
            } else {
                let head = try repo.HEAD()
                if let tag = head as? TagReferenceish, let oid = tag.tagOid {
                    target = oid
                } else {
                    target = head.oid
                }
            }

            let attrsRef = try parent.train?.get().attrsRef
            guard let note = try? repo.note(for: target, notesRef: attrsRef),
                  let attrs = note.attributes.trailers,
                  let value = attrs[key] else {
                throw ExitCode(1)
            }

            guard verbose else {
                Internal.print(value)
                return
            }

            Internal.print("\(key): \(value)")

            if let refName = try? attrsRef ?? repo.defaultNotesRefName,
               let attrLog = try? repo.attributeLog(key: key, target: target, refName: refName),
               let set = attrLog.first(where: { $0.action == .add }) {
                Internal.print(set.commit.noteDescription)
            }
        }
    }

    struct Find: ParsableCommand {
        @OptionGroup()
        var parent: LHC.Options

        @Flag(
            name: .shortAndLong
        )
        var verbose: Bool = false

        @Option()
        var number: Int?

        @Option()
        var since: String?

        @Argument()
        var key: String

        mutating func run() throws {
            Internal.initialize()
            let repo = try Internal.openRepo(at: parent.repo)

            var sinceOID: ObjectID?
            if let since {
                let parsedObject = try repo.object(parsing: since)
                if let tag = parsedObject as? Tagish {
                    sinceOID = tag.target.oid
                } else {
                    sinceOID = parsedObject.oid
                }
            }

            var objects: [ObjectType] = []
            var values: [String] = []
            let attrsRef = try? parent.train?.get().attrsRef
            let tags = try repo.tagsByTarget()
            for commit in try repo.commits(from: repo.HEAD().oid, since: sinceOID) {
                if let commitNote = try? repo.note(for: commit.oid, notesRef: attrsRef),
                   let attrValue = commitNote.attributes.trailers?[key] {
                    objects.append(commit)
                    values.append(attrValue)

                    if let number, objects.count > number {
                        break
                    }
                }

                for tag in tags[commit.oid] ?? [] {
                    if let oid = tag.tagOid,
                       let tagNote = try? repo.note(for: oid, notesRef: attrsRef),
                       let attrValue = tagNote.attributes.trailers?[key] {
                        try objects.append(repo.object(oid))
                        values.append(attrValue)

                        if let number, objects.count > number {
                            break
                        }
                    }
                }
            }

            guard !objects.isEmpty else {
                throw ExitCode(1)
            }

            for (found, value) in zip(objects, values) {
                Internal.print("\(key): \(value)")
                guard verbose,
                   let refName = try? attrsRef ?? repo.defaultNotesRefName,
                   let attrLog = try? repo.attributeLog(key: key, target: found.oid, refName: refName),
                   let set = attrLog.first(where: { $0.action == .add && $0.value == value }) else {
                    continue
                }

                // First, print the item from the attr log.
                Internal.print(set.commit.noteDescription)

                // Then, print the target object itself.
                switch found {
                case let tag as Tagish:
                    Internal.print(tag.description)
                case let commit as Commitish:
                    Internal.print(commit.description)
                default:
                    Internal.print("\(type(of: found).type) \(found.oid)")
                }
            }
        }
    }

    struct Add: ParsableCommand {
        @OptionGroup()
        var parent: LHC.Options

        @Option(name: [.customShort("m"), .customLong("message")])
        var attrLogMessage: String = "Attribute added by 'git-lhc attr add'"

        @Option(help: "Push to a remote after adding the attribute.")
        var push: String?

        @Argument()
        var attribute: ConventionalCommit.Trailer

        @Argument()
        var revision: String?

        mutating func run() throws {
            Internal.initialize()
            var repo = try Internal.openRepo(at: parent.repo)

            let target: ObjectID
            if let revision {
                target = try repo.object(parsing: revision).oid
            } else {
                let head = try repo.HEAD()
                if let tag = head as? TagReferenceish, let oid = tag.tagOid {
                    target = oid
                } else {
                    target = head.oid
                }
            }

            let key = attribute.key
            var message = ""
            let attrsRefString = try parent.train?.get().attrsRef
            if let note = try? repo.note(for: target, notesRef: attrsRefString),
               case let attributes = note.attributes,
               let trailers = attributes.trailers {
                if let value = trailers[key] {
                    guard Internal.promptForConfirmation("\(key) is already defined as '\(value)'.") else {
                        throw AttrError.userAborted
                    }
                }

                if !attributes.body.isEmpty && !attributes.body.isAll(inSet: .whitespacesAndNewlines) {
                    message += attributes.body.trimmingCharacters(in: .newlines) + "\n\n"
                }

                trailers.forEach {
                    guard $0.key != key else { return }
                    message += "\($0.description)\n"
                }
            }

            message += "\(attribute.description)\n"
            Internal.print(message, terminator: "")

            let signingOptions = try parent.signingOptions()
            _ = try repo.createNote(
                for: target,
                message: message,
                author: repo.defaultSignature,
                committer: repo.defaultSignature,
                noteCommitMessage: attrLogMessage,
                notesRefName: attrsRefString,
                force: true
            ) {
                guard let signingOptions else { return nil }
                return try LHC.sign($0, options: signingOptions)
            }

            if let remote = push {
                let refName = try attrsRefString ?? repo.defaultNotesRefName
                let reference = try repo.reference(named: refName)

                try repo.push(
                    remote: remote,
                    reference: reference
                )
            }
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "rm")

        @OptionGroup()
        var parent: LHC.Options

        @Option(name: [.customShort("m"), .customLong("message")])
        var attrLogMessage: String = "Attribute removed by 'git-lhc attr rm'"

        @Argument()
        var key: String

        @Argument()
        var revision: String?

        mutating func run() throws {
            Internal.initialize()
            var repo = try Internal.openRepo(at: parent.repo)

            let target: ObjectID
            if let revision {
                target = try repo.object(parsing: revision).oid
            } else {
                let head = try repo.HEAD()
                if let tag = head as? TagReferenceish, let oid = tag.tagOid {
                    target = oid
                } else {
                    target = head.oid
                }
            }

            let attrsRefString = try parent.train?.get().attrsRef
            guard let note = try? repo.note(for: target, notesRef: attrsRefString),
               case let attributes = note.attributes,
               let trailers = attributes.trailers,
               trailers[key] != nil else {
                throw AttrError.keyNotFound
            }

            let defaultSignature = try repo.defaultSignature
            let signingOptions = try parent.signingOptions()

            guard trailers.count > 1 || !attributes.body.isEmpty else {
                // If the attrs don't have a body and this is the only attribute for the object, remove the git note.
                try repo.removeNote(
                    for: target,
                    author: defaultSignature,
                    committer: defaultSignature,
                    noteCommitMessage: attrLogMessage,
                    notesRefName: attrsRefString
                ) {
                    guard let signingOptions else { return nil }
                    return try LHC.sign($0, options: signingOptions)
                }
                return
            }

            var message = ""
            message = trailers.reduce(into: attributes.body + "\n\n", {
                guard $1.key != key else { return }
                $0 += "\($1.key): \($1.value)\n"
            })

            _ = try repo.createNote(
                for: target,
                message: message,
                author: defaultSignature,
                committer: defaultSignature,
                noteCommitMessage: attrLogMessage,
                notesRefName: attrsRefString,
                force: true
            ) {
                guard let signingOptions else { return nil }
                return try LHC.sign($0, options: signingOptions)
            }
        }
    }

    struct Log: ParsableCommand {
        @OptionGroup()
        var parent: LHC.Options

        @Argument()
        var key: String

        @Argument()
        var revision: String?

        mutating func run() throws {
            Internal.initialize()
            let repo = try Internal.openRepo(at: parent.repo)

            let target: ObjectID
            if let revision {
                target = try repo.object(parsing: revision).oid
            } else {
                let head = try repo.HEAD()
                if let tag = head as? TagReferenceish, let oid = tag.tagOid {
                    target = oid
                } else {
                    target = head.oid
                }
            }

            let attrsRefString = try parent.train?.get().attrsRef ?? repo.defaultNotesRefName
            let log = try repo.attributeLog(key: key, target: target, refName: attrsRefString)

            for entry in log {
                Internal.print(entry)
            }
        }
    }
}

extension Commitish {
    public var noteDescription: String {
        return """
        note \(oid.description)
        Author: \(author.description)
        Date:   \(Internal.gitDateString())

        \(message.indented())
        """
    }
}

enum AttrError: String, Error, CustomStringConvertible {
    case userAborted = "User aborted."
    case keyNotFound = "The specified attribute was not found."

    var description: String {
        rawValue
    }
}
