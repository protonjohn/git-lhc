//
//  Date.swift
//  
//
//  Created by John Biggs on 23.10.23.
//

import Foundation

extension Gluon {
    static var date = { Date.now }

    static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMddHHmm"
        return formatter.string(from: Self.date())
    }
}
