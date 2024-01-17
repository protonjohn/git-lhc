//
//  Interaction.swift
//  
//
//  Created by John Biggs on 13.10.23.
//

import Foundation

public struct InteractiveOption: Equatable {
    public let shortcut: Character
    public let canonicalValue: String
    public let isDefault: Bool
    public let equivalentValues: [String]

    init(
        shortcut: Character,
        canonicalValue: String,
        isDefault: Bool = false,
        equivalentValues: [String]
    ) {
        self.shortcut = shortcut
        self.canonicalValue = canonicalValue
        self.isDefault = isDefault
        self.equivalentValues = equivalentValues
    }

    public var asDefault: Self {
        Self(
            shortcut: shortcut,
            canonicalValue: canonicalValue,
            isDefault: true,
            equivalentValues: equivalentValues
        )
    }

    public static let no = Self(
        shortcut: "n",
        canonicalValue: "No",
        equivalentValues: ["no", "no.", "No.", "N"]
    )

    public static let yes = Self(
        shortcut: "y",
        canonicalValue: "Yes",
        equivalentValues: ["yes", "yes.", "Yes.", "Y"]
    )

    public static let edit = Self(
        shortcut: "e",
        canonicalValue: "Edit",
        equivalentValues: ["ed", "edit", "E"]
    )

    public static let help = Self(
        shortcut: "?",
        canonicalValue: "Help",
        equivalentValues: ["h", "help", "H"]
    )

    public static func ==(lhs: Self, rhs: Self) -> Bool {
        return lhs.canonicalValue == rhs.canonicalValue
    }
}

public typealias InteractiveOptions = Array<InteractiveOption>
public extension InteractiveOptions {
    var help: String {
        return map {
            "\($0.shortcut): \($0.canonicalValue) (\($0.equivalentValues.joined(separator: ", ")))"
        }.joined(separator: "\n")
    }

    var optionString: String {
        return map {
            var result = "\($0.shortcut)"
            if $0.isDefault {
                result = result.uppercased()
            }
            return result
        }.joined(separator: "/")
    }

    func chosenOption(from choiceString: String) -> Element? {
        return first {
            choiceString == "\($0.shortcut)" ||
            choiceString == $0.canonicalValue ||
            $0.equivalentValues.contains(choiceString) ||
            choiceString == "" && $0.isDefault
        }
    }
}


public protocol VerboseCommand {
    var verbose: Bool { get }
}

extension VerboseCommand {
    public func printIfVerbose(_ items: Any..., separator: String = " ", terminator: String = "\n", error: Bool = false) {
        guard verbose else { return }
        
        Internal.shell.print(
            items.map { String(describing: $0) }.joined(separator: separator) + terminator,
            error: error
        )
    }
}

extension Internal {
    public internal(set) static var promptUser: ((String?) -> String?) = {
        if let prompt = $0 {
            Self.print(prompt, terminator: "")
        }
        return readLine()
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
    public func promptForConfirmationIfNotQuiet(_ prompt: String, continueText: Bool = true, defaultAction: Bool = true) -> Bool {
        guard !quiet else { return true }

        return Internal.promptForConfirmation(prompt, continueText: continueText, defaultAction: defaultAction)
    }
}
