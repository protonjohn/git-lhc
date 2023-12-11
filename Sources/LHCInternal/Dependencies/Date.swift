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

    public static func gitDateString() -> String {
        let formatter = DateFormatter()
        // Sun Nov 12 16:20:42 2023 +0100
        formatter.dateFormat = "EEE MMM d HH:MM:SS YYYY Z"
        return formatter.string(from: Self.date())
    }
}
