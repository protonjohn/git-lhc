//
//  Array.swift
//  
//
//  Created by John Biggs on 29.11.23.
//

import Foundation
import LHC
import LHCInternal
import Yams

extension Array {
    var second: Element? {
        guard count > 1 else { return nil }
        return self[1]
    }
}

extension Array<String> {
    var humanReadableDelineatedString: String {
        let secondToLastIndex = index(before: endIndex)
        guard secondToLastIndex > startIndex, let last else { return "" }
        return self[startIndex..<secondToLastIndex].joined(separator: ", ") + ", and \(last)"
    }
}

