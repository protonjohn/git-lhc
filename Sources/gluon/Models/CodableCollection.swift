//
//  CodableCollection.swift
//  
//
//  Created by John Biggs on 27.10.23.
//

import Foundation

indirect enum CodableCollection: Equatable {
    case int(Int)
    case bool(Bool)
    case data(Data)
    case double(Double)
    case string(String)

    case list([Self])
    case dictionary([String: Self])
}

extension CodableCollection: Codable {
    static func decode<T: Decodable>(using item: (T) -> Self, in container: SingleValueDecodingContainer) -> Self? {
        return try? item(container.decode(T.self))
    }

    static func decoder<T: Decodable>(_ item: @escaping (T) -> Self) -> ((SingleValueDecodingContainer) -> Self?) {
        return { Self.decode(using: item, in: $0) }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        let cases = [
            Self.decoder(Self.int),
            Self.decoder(Self.double),
            Self.decoder(Self.string),
            Self.decoder(Self.bool),
            Self.decoder(Self.data),
            Self.decoder(Self.list),
            Self.decoder(Self.dictionary),
        ]

        for closure in cases {
            if let item = closure(container) {
                self = item
                return
            }
        }

        throw CodableCollectionError()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .int(int): try container.encode(int)
        case let .bool(bool): try container.encode(bool)
        case let .data(data): try container.encode(data)
        case let .double(double): try container.encode(double)
        case let .string(string): try container.encode(string)
        case let .list(list): try container.encode(list)
        case let .dictionary(dict): try container.encode(dict)
        }
    }
}

struct CodableCollectionError: Error, CustomStringConvertible {
    let description = "Unsupported value found while decoding file."
}

// MARK: - CodableCollection convenience extensions

extension CodableCollection: ExpressibleByStringLiteral {
    init(stringLiteral value: StringLiteralType) {
        self = .string(value)
    }
}

extension CodableCollection: ExpressibleByIntegerLiteral {
    init(integerLiteral value: IntegerLiteralType) {
        self = .int(value)
    }
}

extension CodableCollection: ExpressibleByBooleanLiteral {
    init(booleanLiteral value: BooleanLiteralType) {
        self = .bool(value)
    }
}

extension CodableCollection: ExpressibleByFloatLiteral {
    init(floatLiteral value: FloatLiteralType) {
        self = .double(value)
    }
}

extension CodableCollection: ExpressibleByArrayLiteral {
    init(arrayLiteral elements: CodableCollection...) {
        self = .list(elements)
    }
}

extension CodableCollection: ExpressibleByDictionaryLiteral {
    init(dictionaryLiteral elements: (String, CodableCollection)...) {
        self = .dictionary(.init(
            elements,
            uniquingKeysWith: { lhs, rhs in
                fatalError("Specified the same key twice: \(lhs) and \(rhs)")
            }
        ))
    }
}
