//
//  ProcessInfo.swift
//  
//
//  Created by John Biggs on 10.10.23.
//

import Foundation

protocol ProcessInfoish {
    var environment: [String: String] { get }
}

extension ProcessInfo: ProcessInfoish {
}

extension Gluon {
    static var processInfo: ProcessInfoish = ProcessInfo.processInfo
}
