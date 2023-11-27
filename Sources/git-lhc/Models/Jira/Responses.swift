//
//  Responses.swift
//  
//
//  Created by John Biggs on 08.11.23.
//

import Foundation

struct SearchResponse: Decodable {
    let maxResults: Int
    let total: Int
    let issues: [Issue]
}
