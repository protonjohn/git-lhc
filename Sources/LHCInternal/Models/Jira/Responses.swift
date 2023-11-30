//
//  Responses.swift
//  
//
//  Created by John Biggs on 08.11.23.
//

import Foundation

public struct SearchResponse: Decodable {
    public let maxResults: Int
    public let total: Int
    public let issues: [Issue]
}
