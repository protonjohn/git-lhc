//
//  MockPrinter.swift
//  
//
//  Created by John Biggs on 13.10.23.
//

import Foundation
import LHCInternal

struct MockPrinter: Printer {
    mutating func print(_ item: String, error: Bool) {
        printedItems.append((item, error))
    }

    var printedItems: [(String, error: Bool)]

    static let mock: Self = .init(printedItems: [])
}
