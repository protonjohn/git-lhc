//
//  Issue.swift
//  
//  Created by John Biggs on 08.11.23.
//

import Foundation
import CodingCollection

public struct Issue: Decodable {
    public let id: String
    public let summary: String?
    public let fields: Fields

    public struct Fields: Decodable {
        static let dateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
            return formatter
        }()

        public let assignee: Assignee?
        public let summary: String
        public let status: Status
        public let fixVersions: [FixVersion]?
        public let description: String?
        public let created: Date

        public let extraFields: [String: Any]

        public func fieldByName(_ name: String) -> Any? {
            extraFields[name]
        }

        enum CodingKeys: String, CaseIterable, CodingKey {
            case assignee
            case summary
            case status
            case fixVersions
            case description
            case created
        }

        public init(
            assignee: Assignee?,
            summary: String,
            status: Status,
            fixVersions: [FixVersion]?,
            description: String?,
            created: Date,
            extraFields: [String : Any]
        ) {
            self.assignee = assignee
            self.summary = summary
            self.status = status
            self.fixVersions = fixVersions
            self.description = description
            self.created = created
            self.extraFields = extraFields
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.assignee = try container.decodeIfPresent(Assignee.self, forKey: .assignee)
            self.summary = try container.decode(String.self, forKey: .summary)
            self.status = try container.decode(Status.self, forKey: .status)
            self.fixVersions = try container.decodeIfPresent([FixVersion].self, forKey: .fixVersions)
            self.description = try container.decodeIfPresent(String.self, forKey: .description)

            let dateString = try container.decode(String.self, forKey: .created)
            guard let date = Self.dateFormatter.date(from: dateString) else {
                var codingPath = decoder.codingPath
                codingPath.append(CodingKeys.created)
                throw DecodingError.dataCorrupted(.init(
                    codingPath: codingPath,
                    debugDescription: """
                        Date was in an unexpected format \
                        (expected \(Self.dateFormatter.dateFormat!), value was \(dateString))
                        """
                ))
            }
            self.created = date

            guard let dictionary = try CodingCollection(from: decoder).value as? [String: Any] else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Couldn't decode extra fields"
                ))
            }

            self.extraFields = dictionary
        }
    }

    public struct FixVersion: Codable {
        let name: String
        let description: String?

        public init(name: String, description: String?) {
            self.name = name
            self.description = description
        }
    }

    public struct Status: Codable {
        let name: String
        let description: String?

        public init(name: String, description: String?) {
            self.name = name
            self.description = description
        }
    }

    public init(id: String, summary: String?, fields: Fields) {
        self.id = id
        self.summary = summary
        self.fields = fields
    }
}
