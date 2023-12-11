//
//  Elements.swift
//  
//
//  Created by John Biggs on 17.11.23.
//

import Foundation
import Parsing
import LHCInternal

/// The build configuration file format used for LHC.
///
/// This is the definition for the general configuration file structure, for values that actually get used by the
/// `git lhc` command, check out ``Train`` and ``Options``.
public struct Configuration {
    public typealias Defines = [Property: String?]

    /// A property in an LHC configuration file.
    public struct Property: RawRepresentable, Hashable, Codable, Comparable, CustomStringConvertible {
        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public var description: String {
            rawValue
        }

        public static let inherited: Self = .init(rawValue: "inherited")
    }

    /// A value to match against in a conditional assignment.
    public struct MatchValue: RawRepresentable, Hashable, Codable, CustomStringConvertible {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public var description: String {
            rawValue
        }
    }

    /// A condition, used in a conditional assignment.
    public enum Condition: Hashable, CustomStringConvertible, Codable {
        /// Require that a property does not exist, or is set to `NO` or `false`.
        case falsey(Property)
        /// Require that a property is set, and is not set to `NO` or `false`.
        case truthy(Property)
        /// Require that a property is set, and is set to a specific value.
        case equals(Property, MatchValue)

        /// The property that this condition is matching against.
        var property: Property {
            switch self {
            case let .falsey(property), let .truthy(property), let .equals(property, _):
                return property
            }
        }

        static func set(_ property: Property, value: String?) -> Set<Self> {
            var result: Set<Self> = []
            if let value {
                result.insert(Value.falseyValues.contains(value) ? .falsey(property) : .truthy(property))
                result.insert(.equals(property, .init(rawValue: value)))
            } else {
                result.insert(.falsey(property))
            }

            return result
        }

        public var description: String {
            switch self {
            case .truthy(let property):
                return "[\(property)]"
            case .falsey(let property):
                return "[!\(property)]"
            case let .equals(property, value):
                return "[\(property)=\(value)]"
            }
        }
    }

    /// The value to set for the property in an assignment.
    public struct Value: Hashable, Codable, CustomStringConvertible {
        typealias StringOrReference = Either<String, Property>

        let interpolatedItems: [StringOrReference]

        public var description: String {
            interpolatedItems.reduce(into: "") { partialResult, item in
                switch item {
                case let .left(string):
                    partialResult += string
                case let .right(variable):
                    partialResult += "$(\(variable))"
                }
            }
        }

        var references: [Property] {
            interpolatedItems.compactMap(\.right)
        }

        static let falseyValues: Set<String> = ["NO", "false", "0"]
    }

    /// Represents a single assignment, conditional or otherwise, in a configuration file.
    public struct Element: Codable, CustomStringConvertible {
        public let property: Property
        public let conditions: Set<Condition>
        public let value: Value

        public var description: String {
            "\(property)\(conditions.map(\.description).joined()) = \(value)"
        }
    }

    public enum Error: Swift.Error {
        case cycle([Property])
        case conditionalAssignment(ofProperty: Property, conditions: [Condition], couldConflictWith: [Property])
        case noInheritedValue(ofElement: Element)
        case noDefaultValueProvided(forProperty: Property)
    }

    /// All of the configuration items in a file.
    public let configItems: [Element]

    init(configItems: [Element]) {
        self.configItems = configItems
    }
}

extension Configuration {
    public internal(set) static var getConfig: ((String) -> Result<Self, Swift.Error>?) = {
        guard let repoUrl = URL(string: $0),
              let configFile = Internal.configFilePath,
              case let configUrl = URL(fileURLWithPath: configFile, relativeTo: repoUrl),
              let contents = Internal.fileManager.contents(atPath: configUrl.path()),
              let string = String(data: contents, encoding: .utf8) else {
            return nil
        }

        do {
            return .success(try Configuration(parsing: string))
        } catch {
            return .failure(error)
        }
    }

    public static var exampleContents: Data? {
        // This implementation is a bit weird because we can't rely on Bundle.module (it only gets generated if we're
        // built with SPM) and we have to use the real, non-stubbed FileManager so we can get the resource's contents
        // without conflicting with any test runs.
        let bundle = Bundle(for: BundleFinder.self)
        let paths = bundle.paths(forResourcesOfType: nil, inDirectory: nil)

        var resourcePath: String?
        for path in paths {
            guard let resourceBundle = Bundle(path: path),
                  let thisResourcePath = resourceBundle.path(forResource: "lhc", ofType: "example") else {
                continue
            }

            resourcePath = thisResourcePath
            break
        }

        guard let resourcePath else { return nil }
        return FileManager.default.contents(atPath: resourcePath)
    }
}

extension Configuration.Error: CustomStringConvertible {
    public var description: String {
        switch self {
        case .cycle(let properties):
            return "Cycle detected among properties \(properties.map(\.description).joined(separator: ", "))."
        case let .conditionalAssignment(property, conditions, conflictingProperties):
            return """
                Property assignment \(property)\(conditions.map(\.description).joined()) could conflict \
                with conditions in the same assignment for properties \
                \(conflictingProperties.map(\.description).joined(separator: ", ")).
                """
        case .noInheritedValue(let element):
            return """
                Element references an inherited value, but has no parent: \(element)
                """

        case .noDefaultValueProvided(let property):
            return """
                No default value was provided for \(property).
                """
        }
    }
}

extension Configuration.Element {
    public init(property: Configuration.Property, conditions: [Configuration.Condition]?, value: Configuration.Value) {
        self.property = property
        self.conditions = Set(conditions ?? [])
        self.value = value
    }
}

extension Configuration.Property: ExpressibleByStringLiteral {
    public init(stringLiteral value: StringLiteralType) {
        self = Self(rawValue: String(value))
    }
}

extension Configuration.Defines {
    func includes(_ property: Key) -> Bool {
        // Because the dictionary is a map of Property -> String?, where `nil` indicates that we've evaluated the
        // property and determined that it's not defined, we can't check `defines[property] == nil`, because that says
        // either the value hasn't been evaluated, or we've evaluated it and determined that it's not defined.
        //
        // So instead we use the hack below:
        // If the outer value is nil, then the map will not be evaluated. Function returns false.
        // Otherwise, if the outer value is non-nil, then the value has been defined, the map will return (), which is
        // not equal to nil, so the function returns true.
        self[property].map { _ in () } != nil
    }

    var stringDict: [String: String] {
        reduce(into: [:]) { partialResult, keypair in
            let (key, value) = keypair
            guard let value else { return }

            partialResult[key.rawValue] = value
        }
    }

    var jsonDict: [String: Any] {
        reduce(into: [String: Any]()) {
            let (key, value) = $1

            guard let value else { return }

            let result: Any
            switch value {
            case "true", "YES":
                result = true
            case "false", "NO":
                result = false
            default:
                if let int = Int(value) {
                    result = int
                } else if let double = Double(value) {
                    result = double
                } else if value.couldBeJSON, // hack until parser is extended
                          let data = value.data(using: .utf8),
                          let object = try? JSONSerialization.jsonObject(with: data) {
                    result = object
                } else {
                    result = value
                }
            }

            $0[key.rawValue] = result
        }
    }
}

/// Not used for anything except letting `Bundle` figure out where we are.
fileprivate class BundleFinder {
}
