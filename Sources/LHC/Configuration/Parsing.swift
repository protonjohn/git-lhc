//
//  Parsing.swift
//
//  Created by John Biggs on 16.11.23.
//

import Foundation
import Parsing

extension Configuration.Property {
    static let allowedInitialCharacters: CharacterSet = .letters.union(.underscore)

    static let parser = Parse(input: Substring.self, Self.init(rawValue:)) {
        Peek {
            Prefix(1, while: Self.allowedInitialCharacters.contains(character:))
        }
        CharacterSet.alphanumerics.union(.underscore).map(String.init)
    }

    static let reference = Parse {
        "$("
        Self.parser
        ")"
    }
}

extension Configuration.Value {
    static let parser = Parse(Self.init(interpolatedItems:)) {
        Many {
            Not {
                "//"
            }

            OneOf {
                Configuration.Property.reference.map(StringOrReference.right)
                OneOf {
                    PrefixUpTo("$(").map(String.init)
                    PrefixUpTo("//").map {
                        String($0.trimmingSuffix(in: .whitespaces))
                    }
                    Rest().map(String.init)
                }.map(StringOrReference.left)
            }

            Skip {
                Optionally {
                    "//"
                    Rest()
                }
            }
        }
    }
}

extension Configuration.MatchValue: Particle {
    static let allowedCharacters: CharacterSet = .alphanumerics
}

extension Configuration.Condition {
    static let parser = Parse {
        "["
        OneOf {
            Parse(Self.equals) {
                Configuration.Property.parser
                "="
                Configuration.MatchValue.parser
            }

            Parse(Self.falsey) {
                "!"
                Configuration.Property.parser
            }

            Configuration.Property.parser.map(Self.truthy)
        }
        "]"
    }
}

extension Configuration.Element {
    static let parser = Parse(Self.init) {
        Configuration.Property.parser
        
        Optionally {
            Many {
                Configuration.Condition.parser
            }
        }
        Skip {
            Whitespace(.horizontal)
        }
        "="
        Skip {
            Whitespace(.horizontal)
        }

        Configuration.Value.parser
    }
}

extension Configuration {
    static let comments = Parse(input: Substring.self) {
        Skip {
            Optionally {
                Many {
                    Whitespace()
                    "//"
                    PrefixUpTo("\n")
                }
            }
            Whitespace()
        }
    }

    static let parser = Parse(Self.init(configItems:)) {
        Self.comments

        Many {
            OneOf {
                PrefixUpTo("\n")
                Rest()
            }.pipe {
                Configuration.Element.parser
            }
        } separator: {
            Self.comments
            Whitespace()
        }
        
        Self.comments
    }
}

public extension Configuration {
    init(parsing contents: String) throws {
        self = try Self.parser.parse(contents[...])
    }
}

protocol Particle: RawRepresentable where RawValue == String {
    static var allowedCharacters: CharacterSet { get }

    init(rawValue: String)
}

extension Particle {
    static var parser: AnyParser<Substring, Self> {
        Self.allowedCharacters.map { Self(rawValue: String($0)) }.eraseToAnyParser()
    }
}

extension CharacterSet {
    static let underscore: CharacterSet = {
        var result: CharacterSet = CharacterSet()
        result.insert("_")
        return result
    }()
}

extension StringProtocol {
    func trimmingSuffix(in set: CharacterSet) -> Self.SubSequence {
        var trimmed = self[...]
        while let last = trimmed.last, set.contains(character: last) {
            trimmed = trimmed.dropLast()
        }

        return trimmed
    }
}
