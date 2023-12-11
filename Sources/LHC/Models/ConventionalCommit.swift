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

    public struct Trailer: Codable, Equatable, CustomStringConvertible, Trailerish {
        public let key: String
        public let value: String

        public init(key: String, value: String) {
            self.key = key
            self.value = value
        }

        public init?(parsing string: String) {
            guard let value = try? Self.parser.parse(string[...]) else { return nil }
            self = value
        }

        public var description: String {
            "\(key): \(value)"
        }
    }

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
            summary: summary
        )
    }
}

fileprivate extension ConventionalCommit.Trailer {
    /// - Bug: The "BREAKING CHANGE" option doesn't parse the text correctly.
    static let parser = Parse(input: Substring.self) {
        Peek { Prefix(1, allowing: .uppercaseLetters) }
        // Trailer key
        OneOf {
            "BREAKING CHANGE".map(String.init)
            "BREAKING-CHANGE".map(String.init)
            CharacterSet.trailerKeyCharacters.map(String.init)
        }
        ": "
        // Trailer value
        OneOf {
            PrefixUpTo("\n").map(String.init)
            Rest().map(String.init)
        }
    }.map { (key: String, value: String) -> Self in
        Self(key: key, value: value)
    }
}

extension Array<ConventionalCommit.Trailer> {
    static func parse(message: Substring) -> (Self, firstTrailerIndex: Int) {
        let lines = message.split(
            separator: "\n",
            omittingEmptySubsequences: false
        )

        var firstTrailerIndex = message.count
        var trailers: [Element] = []
        for line in lines.reversed() {
            guard let trailer = try? Element.parser.parse(line) else {
                // If we hit an empty line near the end of the notes, keep going.
                if line.isEmpty && trailers.isEmpty {
                    continue
                }
                break
            }
            trailers.insert(trailer, at: 0)
            firstTrailerIndex -= (line.count + 1) // account for newline character
        }

        return (trailers, firstTrailerIndex)
    }

    public subscript(_ key: String) -> String? {
        first { $0.key == key }?.value
    }

    public init(message: String) {
        let (trailers, _) = Self.parse(message: message[...])
        self = trailers
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
            maxSplits: 1,
            omittingEmptySubsequences: false
        )

        let subject = components.removeFirst()
        let header = try Header.parser.parse(subject)
        guard let bodyAndMaybeTrailers = components.first else {
            self.init(header: header, body: nil, trailers: [], attributes: attributes)
            return
        }

        let (trailers, firstTrailerIndex) = Array<Trailer>.parse(message: bodyAndMaybeTrailers)
        let bodyEndIndex = bodyAndMaybeTrailers.index(bodyAndMaybeTrailers.startIndex, offsetBy: firstTrailerIndex)
        let body = bodyAndMaybeTrailers[..<bodyEndIndex]

        self.init(
            header: header,
            body: body == "" ? nil : String(body),
            trailers: trailers,
            attributes: attributes
        )
    }

    public func trailers(named name: String) -> [Trailer] {
        trailers.filter { $0.key == name }
    }

    public func versionBump(options: Configuration.Options? = nil) -> VersionBump {
        if isBreaking {
            return .major
        } else if let incrementOption = options?.categoryIncrements?[header.type],
                  let bump = VersionBump(string: incrementOption)  {
            return bump
        } else if header.type.starts(with: "feat") {
            return .minor
        } else {
            return .patch
        }
    }
}

extension Note {
    public var attributes: (body: String, trailers: [ConventionalCommit.Trailer]?) {
        let (trailers, index) = Array<ConventionalCommit.Trailer>.parse(message: message[...])

        guard !trailers.isEmpty else {
            return (message, [])
        }

        let body = message[message.startIndex..<message.index(message.startIndex, offsetBy: index)]
        return (String(body), trailers)
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
    public func versionBump(options: Configuration.Options? = nil) -> ConventionalCommit.VersionBump {
        var result: ConventionalCommit.VersionBump = .patch

        for item in self {
            let thisBump = item.versionBump(options: options)
            if thisBump > result {
                result = thisBump
            }
            if result == .major {
                break
            }
        }

        return result
    }

    public func nextVersion(after versions: [Version], options: Configuration.Options? = nil) -> Version {
        let channel = options?.channel ?? .production

        let sorted = versions.sorted()
        let production = sorted.filter { $0.releaseChannel == .production }

        guard let last = production.last else {
            return Version(0, 0, 1)
        }

        var releaseBump = last.bumping(versionBump(options: options))
        if channel.isPrerelease {
            let channelVersions = versions.filter { $0.releaseChannel == channel }

            if let lastChannelRelease = channelVersions.last,
               lastChannelRelease.shortVersion == releaseBump {
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

    static let scopeCharacters: Self = alphanumericsAndSymbols.union(.punctuationExceptParentheses)
    static let trailerKeyCharacters: Self = alphanumericsAndSymbols.union(.init(charactersIn: "-"))
}
