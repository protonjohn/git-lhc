//
//  File.swift
//  
//
//  Created by John Biggs on 29.11.23.
//

import Foundation
import ArgumentParser
import LHC

extension ReleaseChannel: ExpressibleByArgument {
}

extension ReleaseFormat: ExpressibleByArgument {
}

extension ExpressibleByArgument where Self: CaseIterable & RawRepresentable, RawValue == String {
    static var possibleValues: String { allCases.map(\.rawValue).humanReadableDelineatedString }
}
