//
//  ProcessInfo.swift
//  
//
//  Created by John Biggs on 10.10.23.
//

import Foundation

public protocol ProcessInfoish {
    var arguments: [String] { get }
    var environment: [String: String] { get }
    var processIdentifier: Int32 { get }
    var globallyUniqueString: String { get }
}

extension ProcessInfo: ProcessInfoish {
}

extension Internal {
    public internal(set) static var processInfo: ProcessInfoish = ProcessInfo.processInfo
}
