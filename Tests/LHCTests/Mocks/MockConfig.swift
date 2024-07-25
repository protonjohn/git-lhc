//
//  MockConfig.swift
//
//
//  Created by John Biggs on 11.06.2024.
//

import Foundation
@testable import LHC
@testable import LHCInternal

extension Trains.LinterSettingsImpl {
    public init(
        testProjectIdPrefix: String? = nil,
        maxSubjectLength: Int? = nil,
        maxBodyLineLength: Int? = nil,
        projectIdRegexes: [String] = [],
        projectIdsInBranches: Trains.LintProjectIdsInBranches = .never,
        requireCommitTypes: [String]? = nil
    ) {
        self.init(
            projectIdPrefix: testProjectIdPrefix,
            maxSubjectLength: maxSubjectLength,
            maxBodyLineLength: maxBodyLineLength,
            projectIdRegexes: projectIdRegexes,
            projectIdsInBranches: projectIdsInBranches,
            requireCommitTypes: requireCommitTypes
        )
    }
}

extension Trains.TrailersImpl {
    public init(
        testProjectId: String = "Project-Id",
        releasePipeline: String = "Release-Pipeline",
        failedPipeline: String = "Failed-Pipeline",
        automaticReleaseDate: String = "Automatic-Release-Date",
        releaseImmediately: String = "Release-Immediately",
        mergeRequest: String = "Merge-Request"
    ) {
        self.init(
            projectId: testProjectId,
            releasePipeline: releasePipeline,
            failedPipeline: failedPipeline,
            automaticReleaseDate: automaticReleaseDate,
            releaseImmediately: releaseImmediately,
            mergeRequest: mergeRequest
        )
    }
}

extension Trains.TrainImpl {
    public init(
        testName: String = "test",
        displayName: String? = "Test",
        tagPrefix: String? = "test/",
        releaseChannel: ReleaseChannel = .production,
        attrsRef: String = "refs/notes/attrs",
        checklistsRef: String = "refs/notes/checklist",
        templatesDirectory: String? = nil,
        checklistDirectory: String? = nil,
        versionBumps: [String: Trains.VersionBump] = [:],
        linter: any Trains.LinterSettings = Trains.LinterSettingsImpl(),
        build: (any Trains.BuildSettings)? = nil,
        distribution: Trains.DistributionSettings? = nil,
        trailers: any Trains.Trailers = Trains.TrailersImpl(),
        changelogExcludedTypes: [String]? = nil,
        changelogTypeDisplayNames: [String: String]? = nil,
        userProperties: [String: String]? = nil
    ) {
        self.init(
            name: testName,
            displayName: displayName,
            tagPrefix: tagPrefix,
            releaseChannel: releaseChannel,
            attrsRef: attrsRef,
            checklistsRef: checklistsRef,
            templatesDirectory: templatesDirectory,
            checklistDirectory: checklistDirectory,
            versionBumps: versionBumps,
            linter: linter,
            build: build,
            distribution: distribution,
            trailers: trailers,
            changelogExcludedTypes: changelogExcludedTypes,
            changelogTypeDisplayNames: changelogTypeDisplayNames,
            userProperties: userProperties
        )
    }
}

