//
//  MockJiraClient.swift
//  
//
//  Created by John Biggs on 08.11.23.
//

import Foundation
@testable import git_lhc

struct MockJiraClient: JiraClientish {
    let issues: [Issue]

    func search(query: String) async throws -> [Issue] {
        return issues
    }

    static var mock: Self = .init(issues: [])
    static let customField = "customfield_1234"
}
