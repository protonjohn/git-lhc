//
//  ConventionalCommit.swift
//
//  Contains the necessary data structures and parsing logic for interpreting and
//  creating conventional commit messages.
//
//  Created by John Biggs on 11.10.23.
//

import Foundation
import Parsing
import Version
import SwiftGit2
import LHCInternal

public struct ConventionalCommit: Codable {
    public struct Header: Codable, Equatable {
        public let type: String
        public let scope: String?
        public let isBreaking: Bool
        public let summary: String
    }

    public typealias Trailer = Commit.Trailer

    public enum VersionBump: Codable, Equatable, Comparable {
        case prerelease(channel: String)
        case patch
        case minor
        case major

        public static let `default`: Self = .patch

        public static func < (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.prerelease, _): return true
            case (.patch, .minor): return true
            case (.patch, .major): return true
            case (.minor, .major): return true
            default: return false
            }
        }

        init?(string: String) {
            switch string {
            case "patch":
                self = .patch
            case "minor":
                self = .minor
            case "major":
                self = .major
            default:
                guard let channel = ReleaseChannel(rawValue: string) else {
                    return nil
                }

                self = .prerelease(channel: channel.rawValue)
            }
        }

        init(trainBump: Trains.VersionBump) {
            switch trainBump {
            case .major: self = .major
            case .minor: self = .minor
            case .patch: self = .patch
            }
        }
    }

    public let header: Header
    public let body: String?
    public let trailers: [Trailer]
    public let attributes: [Trailer]? /// These are parsed from git notes.

    public var isBreaking: Bool {
        header.isBreaking ||
            trailers.contains {
                $0.key == "BREAKING-CHANGE" ||
                    $0.key == "BREAKING CHANGE"
            }
    }
}

fileprivate extension ConventionalCommit.Header {
    /// This is used for messages that are formatted by git itself, like reverts and merges.
    /// They're well-formatted and useful enough that we can ingest them as part of the release log.
    /// - Bug: This doesn't handle octopus merges yet, or other less common kinds of merge messages.
    static let formattedMessageParser = Parse(input: Substring.self) {
        /*
         * TODO: handle octopus messages, optional 'into' and 'of', multiple 'of' directives, and merge HEAD messages.
         *
         * Example of a more complicated (if highly unlikely) merge message:
         * Merge branches 'foo', 'bar', 'baz', and 'widget', tags '1.2.3', '2.3.4', '3.4.5' and '4.5.6' of github.com:fred/encabulinator, commit '5268fa491725d0f78eacb0fadd0d3971e08e17d2' and remote-tracking branch 'wilmas-gitlab/fizzbuzz' of gitlab.com:wilma/encabulinator into main
         */
        OneOf {
            Parse {
                "Revert "
                Rest().map { $0.trimmingCharacters(in: .init(charactersIn: "\"").union(.carriageReturn)) }
            }.map {
                Self(type: "revert", scope: nil, isBreaking: false, summary: $0)
            }
            Parse {
                "Merge "
                OneOf {
                    "tag".map { _ in "tag"}
                    "branch".map { _ in "branch" }
                    "commit".map { _ in "commit" }
                    "remote-tracking branch".map { _ in "remote-tracking branch" }
                    // tags, branches, commits, remote-tracking branch(es), HEAD, *optional* 'into' and 'of' (for other remotes)
                    // Example of octopus merge:
                    //
                }
                Skip { " '" }
                PrefixUpTo("'").map(String.init)
                Skip { "' into '" }
                PrefixUpTo("'").map(String.init)
                Skip { Rest() }
            }.map { object, branch, target in
                return Self(type: "merge", scope: "\(object)>\(target)", isBreaking: false, summary: branch)
            }
        }
    }

    static let parser = Parse(input: Substring.self) {
        // Commit type
        CharacterSet.alphanumerics.map(String.init)

        // Commit scope, optional in parentheses
        Optionally {
            "("
            CharacterSet.scopeCharacters
            ")"
        }
        .map { $0 != nil ? String($0!) : nil }

        // Whether or not it's a breaking change (can also be determined by the footer)
        Optionally { "!" }
            .map { $0 != nil }

        ": "

        // The remainder of the commit subject is the summary of the change.
        OneOf {
            PrefixUpTo("\n").map(String.init)
            Rest().map(String.init)
        }
    }.map { (type: String, scope: String?, isBreaking: Bool, summary: String) -> Self in
        Self(
            type: type,
            scope: scope,
            isBreaking: isBreaking,
            summary: summary.trimmingCharacters(in: .carriageReturn)
        )
    }
}

extension ConventionalCommit.Trailer: CustomStringConvertible {
    public var description: String {
        "\(key): \(value)"
    }
}

extension ConventionalCommit.Trailer {
    public static func trailers(from message: String) throws -> (body: String, trailers: [Self]) {
        // Get the start index of each paragraph in the string. The regex matches either the start of the string, or at
        // least two newlines that aren't followed by the end of the string.
        let paragraphs = message.matches(of: try Regex("(((\r\n|\r|\n){2,}(?!$))|^)"))
        let startOfLastParagraph = paragraphs.last!.range.lowerBound

        let lastParagraph = message[startOfLastParagraph..<message.endIndex]
        let lines = lastParagraph.split { $0.isNewline }

        var trailers: [Self] = []
        for line in lines.reversed() {
            guard let trailer = try? Self.parser.parse(line) else {
                return (message, [])
            }

            trailers.insert(trailer, at: 0)
        }

        return (String(message[message.startIndex..<startOfLastParagraph]), trailers)
    }

    /// - Bug: The "BREAKING CHANGE" option doesn't parse the text correctly.
    fileprivate static let parser = Parse(input: Substring.self) {
        Peek { Prefix(1, allowing: .uppercaseLetters) }
        // Trailer key
        OneOf {
            "BREAKING CHANGE".map({ _ in "BREAKING-CHANGE" })
            CharacterSet.trailerKeyCharacters.map(String.init)
        }
        ": "
        // Trailer value
        OneOf {
            PrefixUpTo("\n").map(String.init)
            Rest().map(String.init)
        }
    }.map { (key: String, value: String) -> Self in
        Self(key: key, value: value.trimmingCharacters(in: .carriageReturn))
    }
}

extension Array<ConventionalCommit.Trailer>: CustomStencilSubscriptable {
    public subscript(key: String) -> String? {
        first { $0.key == key }?.value
    }
}

extension ConventionalCommit.Header {
    public init(subject: String) throws {
        self = try Self.parser.parse(subject)
    }

}

extension ConventionalCommit {
    /// Create a ConventionalCommit object by parsing a commit message.
    ///
    /// If the first line can't be parsed into a conventional commit, this function will throw an error. This function
    /// will also iterate over the lines in the commit body, starting at the end, to look for any commit trailers.
    ///
    /// It will then assume that the commit body is anything that is not the commit subject or one of the trailers.
    public init(message: String, attributes: [Trailer]? = nil) throws {
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        var components = message.split(
            separator: "\n",
            maxSplits: 1
        )

        let header: Header
        guard !components.isEmpty else {
            throw ReleaseError.invalidVersion("")
        }

        let subject = components.removeFirst()

        if let formattedHeader = Self.parseMergeOrRevertCommit(subject: String(subject)) {
            header = formattedHeader
        } else {
            header = try Header.parser.parse(subject)
        }

        guard !components.isEmpty else {
            self.init(header: header, body: nil, trailers: [], attributes: attributes)
            return
        }

        let remainder = components.first!.trimmingPrefix(while: \.isWhitespace)
        let (body, trailers) = try Trailer.trailers(from: String(remainder))

        self.init(
            header: header,
            body: body == "" ? nil : String(body).trimmingCharacters(in: .carriageReturn),
            trailers: trailers,
            attributes: attributes
        )
    }

    public static func parseMergeOrRevertCommit(subject: String) -> Header? {
        guard subject.hasPrefix("Merge") || subject.hasPrefix("Revert") else {
            return nil
        }

        return try? Header.formattedMessageParser.parse(subject)
    }

    public func trailers(named name: String) -> [Trailer] {
        trailers.filter { $0.key == name }
    }

    public func versionBump(train: Trains.TrainImpl? = nil) -> VersionBump {
        if isBreaking {
            return .major
        } else if let increment = train?.versionBumps[header.type] {
            return .init(trainBump: increment)
        } else if header.type.starts(with: "feat") {
            return .minor
        } else {
            return .patch
        }
    }

    public func matchesPolicy(in linterSettings: any Trains.LinterSettings) ->
                    (policy: any Trains.LinterPolicyItem, target: String)? {
        let policies: [(KeyPath<any Trains.LinterSettings, (any Trains.LinterPolicyItem)?>)] = [
            \.commitTypes,
            \.commitScopes,
            \.commitTrailers,
        ]

        for keyPath in policies {
            guard let policyValue = linterSettings[keyPath: keyPath] else {
                continue
            }

            let policy = policyValue.policy

            let inputValues: [String]?
            let target: String
            switch keyPath {
            case \.commitTypes:
                inputValues = [header.type]
                target = "type"
            case \.commitScopes:
                inputValues = header.scope.map { [$0] }
                target = "scope"
            case \.commitTrailers:
                inputValues = trailers.map { $0.key }
                target = "trailer"
            default:
                fatalError("Unexpected policy \(policy)")
            }

            switch policyValue.policy {
            case .allow:
                guard let inputValues else { continue }

                guard inputValues.allSatisfy({
                    policyValue.items.contains($0)
                }) else {
                    return (policyValue, target)
                }

            case .deny:
                guard let inputValues else { continue }

                guard inputValues.allSatisfy({
                    !policyValue.items.contains($0)
                }) else {
                    return (policyValue, target)
                }

            case .require:
                guard !policyValue.items.isEmpty, let inputValues else {
                    return (policyValue, target)
                }

                guard inputValues.allSatisfy({
                    policyValue.items.contains($0)
                }) else {
                    return (policyValue, target)
                }
            }
        }

        return nil
    }
}

extension ConventionalCommit: CustomStringConvertible {
    public var description: String {
        var result = "\(header.type)"

        if let scope = header.scope {
            result += "(\(scope))"
        }

        result += "\(isBreaking ? "!" : ""): \(header.summary)"

        if let body {
            result = """
            \(result)

            \(body)
            """
        }

        if !trailers.isEmpty {
            result = """
            \(result)

            \(trailers.map { "\($0.key): \($0.value)" }.joined(separator: "\n"))
            """
        }

        return result
    }
}

extension Array<ConventionalCommit> {
    public func versionBump(train: Trains.TrainImpl? = nil) -> ConventionalCommit.VersionBump {
        var result: ConventionalCommit.VersionBump = .patch

        for item in self {
            let thisBump = item.versionBump(train: train)
            if thisBump > result {
                result = thisBump
            }
            if result == .major {
                break
            }
        }

        return result
    }

    public func nextVersion(after versions: [Version], train: Trains.TrainImpl?) -> Version {
        let channel = train?.releaseChannel ?? .production

        let sorted = versions.sorted()
        let production = sorted.filter { $0.releaseChannel == .production }

        guard let last = production.last else {
            return Version(0, 0, 1)
        }

        var releaseBump = last.bumping(versionBump(train: train))
        if channel.isPrerelease {
            // If we're in a prerelease channel, check to see if any other prereleases exist with the same shortVersion.
            // We want to make sure that the prerelease number is always unique among the releases that already exist.
            let channelVersions = versions.filter {
                $0.releaseChannel == channel && $0.shortVersion == releaseBump
            }

            if let lastChannelRelease = channelVersions.last {
                releaseBump = lastChannelRelease
            }
            return releaseBump.bumpingPrerelease(channel: channel.rawValue)
        } else {
            return releaseBump
        }
    }
}

extension Prefix where Input: StringProtocol {
    init<R: CountingRange>(_ length: R, allowing allowed: CharacterSet) {
        self.init(length, while: allowed.contains(character:))
    }
}

extension String {
    var isOneWord: Bool {
        !self.trimmingCharacters(in: .whitespacesAndNewlines)
            .contains(where: CharacterSet.whitespacesAndNewlines.contains(character:))
    }
}

extension CharacterSet {
    static let alphanumericsAndSymbols: Self = .alphanumerics.union(.symbols)
    static let punctuationExceptParentheses: Self = .punctuationCharacters.subtracting(.init(charactersIn: "()"))
    static let carriageReturn: Self = .init(charactersIn: "\r")

    static let scopeCharacters: Self = alphanumericsAndSymbols.union(.punctuationExceptParentheses)
    static let trailerKeyCharacters: Self = alphanumericsAndSymbols.union(.init(charactersIn: "-"))
}
