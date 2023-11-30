//
//  Date.swift
//  
//
//  Created by John Biggs on 23.10.23.
//

import Foundation

extension Internal {
    public internal(set) static var date = { Date.now }

    public static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMddHHmm"
        return formatter.string(from: Self.date())
    }
}
