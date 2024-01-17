//
//  File.swift
//  
//
//  Created by John Biggs on 10.10.23.
//

import Foundation
@testable import git_lhc
import SwiftGit2
import Yams

extension OID {
    static func random() -> Self {
        var item = OID.RawValue()
        withUnsafeMutableBytes(of: &item) {
            let buf = $0.bindMemory(to: UInt8.self)
            for i in 0..<buf.count {
                buf[i] = UInt8.random(in: 0..<UInt8.max)
            }
        }

        return Self(rawValue: item)
    }
}

extension Array {
    var second: Element? {
        guard count >= 2 else {
            return nil
        }

        return self[1]
    }
}

extension String: Error {
}
