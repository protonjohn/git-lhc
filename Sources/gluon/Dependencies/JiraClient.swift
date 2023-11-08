//
//  JiraClient.swift
//  
//
//  Created by John Biggs on 08.11.23.
//

import Foundation

protocol JiraClientish {
    func search(query: String) async throws -> [Issue]
}

extension JiraClientish {
    func issues(ids: [String]) async throws -> [Issue] {
        try await search(query: "Issuekey in (\(ids.joined(separator: ",")))")
    }
}

struct JiraClient: JiraClientish {
    static let decoder = JSONDecoder()

    let apiEndpoint: URL
    let auth: Either<UserAuth, BearerToken>

    var restEndpoint: URL {
        apiEndpoint
            .appending(component: "rest")
            .appending(component: "api")
            .appending(component: "2")
    }

    typealias BearerToken = String

    struct UserAuth {
        let user: String
        let password: String

        var authorizationString: String {
            guard let data = "\(user):\(password)".data(using: .utf8) else {
                fatalError("Could not encode user auth data. Does it contain an illegal character?")
            }
            return data.base64EncodedString()
        }
    }
}

extension JiraClient {
    init(apiEndpoint: URL, bearerToken: String) {
        self.init(apiEndpoint: apiEndpoint, auth: .right(bearerToken))
    }

    init(apiEndpoint: URL, userAuth: UserAuth) {
        self.init(apiEndpoint: apiEndpoint, auth: .left(userAuth))
    }
}

extension JiraClient {
    enum Route: String {
        case search
    }

    private func fetch<T: Decodable>(_ type: T.Type, from route: Route, queryItems: [URLQueryItem] = []) async throws -> T {
        let routeURL = restEndpoint
            .appending(path: route.rawValue, directoryHint: .notDirectory)
            .appending(queryItems: queryItems)

        let authorization: String
        switch auth {
        case .left(let userAuth):
            authorization = "Basic \(userAuth.authorizationString)"
        case .right(let bearerToken):
            authorization = "Bearer \(bearerToken)"
        }

        var request = URLRequest(url: routeURL)
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await Gluon.urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw JiraClientError.unexpectedResponseType(response)
        }

        guard httpResponse.statusCode == 200 else {
            throw JiraClientError.statusCode(httpResponse.statusCode, data)
        }

        return try Self.decoder.decode(T.self, from: data)
    }

    func search(query: String) async throws -> [Issue] {
        let response = try await fetch(SearchResponse.self, from: .search, queryItems: [.init(name: "jql", value: query)])
        return response.issues
    }
}

enum JiraClientError: Error, CustomStringConvertible {
    case unexpectedResponseType(URLResponse)
    case statusCode(Int, Data)

    var description: String {
        switch self {
        case .unexpectedResponseType(let urlResponse):
            return "Unexpected response type: \(type(of: urlResponse))"
        case .statusCode(let int, let data):
            var result = "HTTP \(int)"
            if let body = String(data: data, encoding: .utf8) {
                result += ":\n\(body)"
            }
            return result
        }
    }
}

extension Gluon {
    static var urlSession = URLSession.shared

    static var jiraClient: JiraClientish? = {
        guard let endpoint = GluonEnvironment.jiraEndpoint.value else { return nil }
        guard let url = URL(string: endpoint) else {
            fatalError("'\(endpoint)' (specified by \(GluonEnvironment.jiraEndpoint.rawValue)) is not a valid URL")
        }

        if let token = GluonEnvironment.jiraApiToken.value {
            return JiraClient(apiEndpoint: url, bearerToken: token)
        } else if let username = GluonEnvironment.jiraUsername.value {
            guard let password = Gluon.promptForPassword("Enter Jira password: ") else { return nil }
            return JiraClient(apiEndpoint: url, userAuth: .init(user: username, password: password))
        }

        return nil
    }()
}
