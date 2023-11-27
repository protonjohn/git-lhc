//
//  Version.swift
//  
//
//  Created by John Biggs on 13.10.23.
//

import Foundation
import Version

extension Version {
    var shortVersion: Self {
        Version(major, minor, patch)
    }

    func prereleaseIdentifier(after identifier: String?) -> String {
        guard let identifier, let value = Int(identifier) else {
            return "1"
        }
        return "\(value + 1)"
    }

    func bumpingPrerelease(channel: String) -> Self {
        var identifiers = prereleaseIdentifiers

        if let index = identifiers.firstIndex(of: channel) {
            if index == identifiers.endIndex {
                identifiers.append(prereleaseIdentifier(after: nil))
            } else {
                let nextIndex = identifiers.index(after: index)
                let identifier = identifiers[nextIndex]

                identifiers[nextIndex] = prereleaseIdentifier(after: identifier)
            }
        } else {
            identifiers = [channel, prereleaseIdentifier(after: nil)] + identifiers
        }

        return Self(major, minor, patch, pre: identifiers)
    }

    func bumping(_ bump: ConventionalCommit.VersionBump) -> Self {
        switch bump {
        case .prerelease(let channel):
            return self.bumpingPrerelease(channel: channel)
        case .patch:
            return Self(major: major, minor: minor, patch: patch + 1)
        case .minor:
            return Self(major: major, minor: minor + 1, patch: 0)
        case .major:
            return Self(major: major + 1, minor: 0, patch: 0)
        }
    }

    func adding(
        prereleaseIdentifiers: [String] = [],
        buildIdentifiers: [String] = []
    ) -> Self {
        Version(
            major,
            minor,
            patch,
            pre: self.prereleaseIdentifiers + prereleaseIdentifiers,
            build: self.buildMetadataIdentifiers + buildIdentifiers
        )
    }

    init?(prefix: String?, versionString: String) {
        var versionString = versionString

        if let prefix {
            guard versionString.starts(with: prefix) else { return nil }
            versionString = String(versionString[prefix.endIndex...])
        }

        guard let version = Version(versionString) else { return nil }
        self = version
    }
}
