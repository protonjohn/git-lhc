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

struct ConventionalCommit: Codable {
    struct Header: Codable, Equatable {
        let type: String
        let scope: String?
        let isBreaking: Bool
        let summary: String
    }

    struct Trailer: Codable, Equatable, Trailerish {
        let key: String
        let value: String
    }

    enum VersionBump: Codable, Equatable, Comparable {
        case prerelease(channel: String)
        case patch
        case minor
        case major

        static let `default`: Self = .patch

        static func < (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.prerelease, _): return true
            case (.patch, .minor): return true
            case (.patch, .major): return true
            case (.minor, .major): return true
            default: return false
            }
        }
    }

    let header: Header
    let body: String?
    let trailers: [Trailer]

    var isBreaking: Bool {
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

extension ConventionalCommit {
    /// Create a ConventionalCommit object by parsing a commit message.
    ///
    /// If the first line can't be parsed into a conventional commit, this function will throw an error. This function
    /// will also iterate over the lines in the commit body, starting at the end, to look for any commit trailers.
    ///
    /// It will then assume that the commit body is anything that is not the commit subject or one of the trailers.
    init(message: String) throws {
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = message.split(
            separator: "\n",
            omittingEmptySubsequences: false
        )

        let subject = lines.removeFirst()
        let header = try Header.parser.parse(subject)

        var firstTrailerIndex = lines.count
        var trailers: [Trailer] = []
        for (index, element) in lines.enumerated().reversed() {
            guard let trailer = try? Trailer.parser.parse(element) else {
                break
            }
            trailers.insert(trailer, at: 0)
            firstTrailerIndex = index
        }

        let body = lines[..<firstTrailerIndex]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        self.init(
            header: header,
            body: body == "" ? nil : body,
            trailers: trailers
        )
    }

    func trailers(named name: String) -> [Trailer] {
        trailers.filter { $0.key == name }
    }

    var versionBump: VersionBump {
        let categories = Configuration.configuration.commitCategories

        if isBreaking {
            return .major
        } else if let increment = categories?.first(where: {
                $0.name == header.type && $0.increment != nil
            })?.increment {
            return increment
        } else {
            return .patch
        }
    }
}

extension ConventionalCommit: CustomStringConvertible {
    var description: String {
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
    var versionBump: ConventionalCommit.VersionBump {
        var result: ConventionalCommit.VersionBump = .patch

        for item in self {
            let thisBump = item.versionBump
            if thisBump > result {
                result = thisBump
            }
            if result == .major {
                break
            }
        }

        return result
    }

    func nextVersion(after previous: Version, prereleaseChannel: String? = nil) -> Version {
        if let prereleaseChannel {
            if previous.isPrerelease {
                return previous
                    .bumping(.prerelease(channel: prereleaseChannel))
            } else {
                return previous
                    .bumping(versionBump)
                    .bumpingPrerelease(channel: prereleaseChannel)
            }
        } else {
            return previous.bumping(versionBump)
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

    func contains(character: Character) -> Bool {
        character.unicodeScalars.allSatisfy(contains(_:))
    }
}
