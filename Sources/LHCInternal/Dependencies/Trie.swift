//
//  Trie.swift
//
//  Simple trie implementation for figuring out the minimum number of characters needed
//  to losslessly represent a git OID in a repository.
//
//  Created by John Biggs on 09.07.2024.
//

import Foundation

struct Trie<T: Hashable> {
    struct TrieNode {
        let value: T?
        var children: [TrieNode]

        @discardableResult
        mutating func insert(_ value: Array<T>, prefixLength: Int = 0) -> Int {
            var value = value
            guard !value.isEmpty else {
                children.append(.init(value: nil, children: []))
                return 0
            }

            let element = value.removeFirst()
            if let index = children.firstIndex(where: { $0.value == element }) {
                return children[index].insert(value, prefixLength: prefixLength + 1)
            } else {
                var node = TrieNode(value: element, children: [])
                node.insert(value)
                children.append(node)
                return prefixLength
            }
        }
    }

    var maxPrefix = 0
    var count = 0
    var root = TrieNode(value: nil, children: [])

    mutating func insert(_ value: Array<T>) {
        maxPrefix = Swift.max(maxPrefix, root.insert(value))
        count += 1
    }

    init() {}
}

extension Trie {
    mutating func insert(string: String) where T == Character {
        insert(Array(string))
    }

    mutating func insert(data: Data) where T == UInt8 {
        insert(Array(data))
    }

    mutating func insert(oid: ObjectID) where T == UInt8 {
        var oid = oid.rawValue
        withUnsafeBytes(of: &oid) { oidBuf in
            insert(Array(oidBuf))
        }
    }
}

public extension ObjectID {
    static func minimumLength(toLosslesslyRepresentStringsOf oids: any Collection<ObjectID>, floor: Int? = nil) -> Int {
        var trie = Trie<UInt8>()
        for oid in oids {
            trie.insert(oid: oid)
        }
        // Multiply by two to allow for hexadecimal representation
        return max(trie.maxPrefix * 2, floor ?? 0)
    }

    static func minimumLength(toLosslesslyRepresentOidStrings oidStrings: any Collection<String>, floor: Int? = nil) -> Int {
        var trie = Trie<Character>()
        for oidString in oidStrings {
            trie.insert(string: oidString)
        }
        return max(trie.maxPrefix, floor ?? 0)
    }
}
