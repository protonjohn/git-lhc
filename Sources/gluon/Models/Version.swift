//
//  Version.swift
//  
//
//  Created by John Biggs on 13.10.23.
//

import Foundation
import Version

extension Version {
    var isPrerelease: Bool {
        !prereleaseIdentifiers.isEmpty
    }

    func prerelease() -> Self {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMddHHmm"
        let dateString = formatter.string(from: .now)

        return Version(major, minor, patch, pre: [dateString])
    }

    func bumping(_ bump: ConventionalCommit.VersionBump) -> Self {
        switch bump {
        case .patch:
            return Self(major: major, minor: minor, patch: patch + 1)
        case .minor:
            return Self(major: major, minor: minor + 1, patch: 0)
        case .major:
            return Self(major: major + 1, minor: 0, patch: 0)
        }
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
