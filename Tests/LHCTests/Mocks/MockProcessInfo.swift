//
//  File.swift
//  
//
//  Created by John Biggs on 10.10.23.
//

import Foundation
import LHCInternal

struct MockProcessInfo: ProcessInfoish {
    let environment: [String : String]

    func with<E: EnvironmentVariable>(envVar: E, setTo value: String) -> Self {
        var environment = environment
        environment[envVar.key] = value
        return Self(environment: environment)
    }

    static let mock: Self = .init(environment: [:])
}
