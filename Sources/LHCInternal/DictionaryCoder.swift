//
//  DictionaryCoder.swift
//
//  Created by John Biggs on 15.01.24.
//

import Foundation

/// A dummy coding key struct for parsing keys of a dictionary.
public struct CodingDictionaryKey: CodingKey {
    public var stringValue: String
    public var intValue: Int?

    init(stringValue: String, intValue: Int? = nil) {
        self.stringValue = stringValue
        self.intValue = intValue
    }

    public init?(intValue: Int) {
        self.init(
            stringValue: .init(intValue),
            intValue: intValue
        )
    }

    public init?(stringValue: String) {
        self.init(stringValue: stringValue, intValue: nil)
    }
}

/// A dummy wrapper around a `[String: Any]` dictionary, which when used in combination with the extensions below
/// allow for encoding heterogeneous collections.
public struct CodingDictionary: RawRepresentable, ExpressibleByDictionaryLiteral, Codable {
    typealias CodingKeys = CodingDictionaryKey
    public let rawValue: [String: Any]

    public init(rawValue: [String: Any]) {
        self.rawValue = rawValue
    }

    public subscript(_ key: String) -> Any? {
        rawValue[key]
    }

    public init(dictionaryLiteral elements: (String, Any)...) {
        self.rawValue = .init(uniqueKeysWithValues: elements)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(rawValue: container.decode([String : Any].self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rawValue)
    }
}

extension KeyedDecodingContainer<CodingDictionaryKey> {
    public func decode(_ type: [String: Any].Type, forKey key: K) throws -> [String: Any] {
        try nestedContainer(keyedBy: K.self, forKey: key).decode(type)
    }

    public func decode(_ type: [Any].Type, forKey key: K) throws -> [Any] {
        var container = try nestedUnkeyedContainer(forKey: key)
        return try container.decode([Any].self)
    }

    public func decode(_ type: [String: Any].Type) throws -> [String: Any] {
        var result: [String: Any] = [:]

        for key in allKeys {
            let stringKey = key.stringValue
            if let bool = try? decode(Bool.self, forKey: key) {
                result[stringKey] = bool
            } else if let int = try? decode(Int.self, forKey: key) {
                result[stringKey] = int
            } else if let double = try? decode(Double.self, forKey: key) {
                result[stringKey] = double
            } else if let string = try? decode(String.self, forKey: key) {
                result[stringKey] = string
            } else if let data = try? decode(Data.self, forKey: key) {
                result[stringKey] = data
            } else if let dict = try? decode([String: Any].self, forKey: key) {
                result[stringKey] = dict
            } else if let array = try? decode([Any].self, forKey: key) {
                result[stringKey] = array
            }
        }

        return result
    }
}

extension UnkeyedDecodingContainer {
    public mutating func decode(_ type: [String: Any].Type) throws -> [String: Any] {
        try nestedContainer(keyedBy: CodingDictionaryKey.self).decode(type)
    }

    public mutating func decode(_ type: [Any].Type) throws -> [Any] {
        var result: [Any] = []

        if let bool = try? decode(Bool.self) {
            result.append(bool)
        } else if let int = try? decode(Int.self) {
            result.append(int)
        } else if let double = try? decode(Double.self) {
            result.append(double)
        } else if let string = try? decode(String.self) {
            result.append(string)
        } else if let data = try? decode(Data.self) {
            result.append(data)
        } else if let dict = try? decode([String: Any].self) {
            result.append(dict)
        } else if let array = try? decode([Any].self) {
            result.append(array)
        }

        return result
    }
}

extension KeyedEncodingContainer<CodingDictionaryKey> {
    public mutating func encode(_ dict: [String: Any]) throws {
        for (key, value) in dict {
            let codingKey = K(stringValue: key, intValue: nil)
            switch value {
            case let bool as Bool:
                try encode(bool, forKey: codingKey)
            case let int as Int:
                try encode(int, forKey: codingKey)
            case let double as Double:
                try encode(double, forKey: codingKey)
            case let string as String:
                try encode(string, forKey: codingKey)
            case let data as Data:
                try encode(data, forKey: codingKey)
            case let innerDict as [String: Any]:
                var container = nestedContainer(keyedBy: K.self, forKey: codingKey)
                try container.encode(innerDict)
            case let innerArray as [Any]:
                var container = nestedUnkeyedContainer(forKey: codingKey)
                try container.encode(innerArray)
            default:
                let codingPath = codingPath + [codingKey]
                throw EncodingError.invalidValue(
                    value,
                    .init(
                        codingPath: codingPath,
                        debugDescription: "In \(#function), \(#file):\(#line)"
                    )
                )
            }
        }
    }
}

extension UnkeyedEncodingContainer {
    mutating func encode(_ array: [Any]) throws {
        for item in array {
            switch item {
            case let bool as Bool:
                try encode(bool)
            case let int as Int:
                try encode(int)
            case let double as Double:
                try encode(double)
            case let string as String:
                try encode(string)
            case let data as Data:
                try encode(data)
            case let innerDict as [String: Any]:
                var container = self.nestedContainer(keyedBy: CodingDictionaryKey.self)
                try container.encode(innerDict)
            case let innerArray as [Any]:
                var container = self.nestedUnkeyedContainer()
                try container.encode(innerArray)
            default:
                throw EncodingError.invalidValue(
                    item,
                    .init(
                        codingPath: codingPath,
                        debugDescription: "In \(#function), \(#file):\(#line)"
                    )
                )
            }
        }
    }
}
