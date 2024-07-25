//
//  ConfigLoader.swift
//
//
//  Created by John Biggs on 11.06.2024.
//

import Foundation
import PklSwift

struct BundleModuleReader: ModuleReader {
    /// Config files can import PKL resources packaged with this Swift package if they use `lhc://` in the URL.
    let scheme = "lhc"
    let isLocal = true
    let isGlobbable = false
    let hasHierarchicalUris = false

    func listElements(uri: URL) async throws -> [PathElement] {
        /// `PathElement` isn't actually instantiable anyway since the init routine is internal. It still seems to work
        /// if we return an empty list though.
        return []
    }

    func read(url: URL) async throws -> String {
        let name = url.deletingPathExtension().lastPathComponent
        let pathExtension = url.pathExtension

        /// If the config file contains a line like `extends "lhc:///Trains.pkl"`, this will load the resource `Train` of
        /// the type `pkl`.
        guard let path = Bundle.module.path(forResource: name, ofType: pathExtension) else {
            throw POSIXError(.EINVAL)
        }

        guard let contents = Internal.fileManager.contents(atPath: path),
              let string = String(data: contents, encoding: .utf8) else {
            throw POSIXError(.ENOENT)
        }

        return string
    }
}

class LHCInternalBundle {
}

extension Trains {
    static func loadTrains(
        source: ModuleSource,
        properties: [String: String],
        completion: @escaping (Result<[Trains.TrainImpl], Error>) -> ())
    {
        Task.detached {
            let options = EvaluatorOptions(
                allowedModules: [".*"],
                allowedResources: [".*"],
                moduleReaders: [BundleModuleReader()],
                env: Internal.processInfo.environment,
                properties: properties
            )
            do {
                try await withEvaluator(options: options) { evaluator in
                    let trains = try await evaluator.evaluateModule(source: source, as: Trains.ModuleImpl.self)
                    completion(.success(trains.trains as! [Trains.TrainImpl]))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    @available(*, noasync, message: "This function is not available from an async context.")
    public static func loadTrains(source: ModuleSource, properties: [String: String]) throws -> [Trains.TrainImpl] {
        let group = DispatchGroup()
        group.enter()

        var result: Result<[Trains.TrainImpl], Error>?
        loadTrains(source: source, properties: properties) {
            result = $0
            group.leave()
        }

        group.wait()
        switch result {
        case nil:
            fatalError("Did not expect nil result from config evaluation.")
        case .success(let trains):
            return trains
        case .failure(let error):
            throw error
        }
    }
}

extension Internal {
    public static var loadTrains: (([String: String]) throws -> [Trains.TrainImpl]?) = { properties in
        guard let configFilePath = LHCEnvironment.configFilePath.value else {
            return nil
        }

        return try Trains.loadTrains(source: .path(configFilePath), properties: properties)
    }
}

extension Trains.Train {
    public var checklistRefRootWithTrailingSlash: String? {
        var checklistsRef = self.checklistsRef
        while checklistsRef.hasSuffix("/") {
            checklistsRef.removeLast()
        }
        checklistsRef.append("/")
        return checklistsRef
    }
}

extension Trains.TrainImpl: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PklCodingKey.self)
        try container.encode(name, forKey: PklCodingKey(string: "name"))
        try container.encode(attrsRef, forKey: PklCodingKey(string: "attrsRef"))
        try container.encode(tagPrefix, forKey: PklCodingKey(string: "tagPrefix"))
        try container.encode(displayName, forKey: PklCodingKey(string: "displayName"))
        try container.encode(checklistsRef, forKey: PklCodingKey(string: "checklistsRef"))
        try container.encode(templatesDirectory, forKey: PklCodingKey(string: "templatesDirectory"))
        try container.encode(checklistDirectory, forKey: PklCodingKey(string: "checklistDirectory"))
        try container.encode(releaseChannel.rawValue, forKey: PklCodingKey(string: "releaseChannel"))

        try container.encode(userProperties, forKey: PklCodingKey(string: "userProperties"))

        let bumps = versionBumps.mapValues(\.rawValue)
        try container.encode(bumps, forKey: PklCodingKey(string: "versionBumps"))

        let linter = self.linter as! Trains.LinterSettingsImpl
        try container.encode(linter, forKey: PklCodingKey(string: "linter"))

        if let build = self.build as? Trains.BuildSettingsImpl {
            try container.encode(build, forKey: PklCodingKey(string: "build"))
        }

        var distributionContainer = container.nestedContainer(keyedBy: PklCodingKey.self, forKey: PklCodingKey(string: "distribution"))
        switch distribution {
        case .appStore(let appStore):
            guard let appStoreImpl = appStore as? Trains.AppStoreImpl else { break }
            try distributionContainer.encode(appStoreImpl, forKey: PklCodingKey(string: "appStore"))
        case .sparkle(let sparkle):
            guard let sparkleImpl = sparkle as? Trains.SparkleImpl else { break }
            try distributionContainer.encode(sparkleImpl, forKey: PklCodingKey(string: "sparkle"))
        case .customDistribution(let custom):
            guard let customImpl = custom as? Trains.CustomDistributionImpl else { break }
            try distributionContainer.encode(customImpl, forKey: PklCodingKey(string: "custom"))
        case nil:
            break
        }

        if let trailers = self.trailers as? Trains.TrailersImpl {
            try container.encode(trailers, forKey: PklCodingKey(string: "trailers"))
        }

        try container.encode(changelogExcludedTypes, forKey: PklCodingKey(string: "changelogExcludedTypes"))
        try container.encode(changelogTypeDisplayNames, forKey: PklCodingKey(string: "changelogTypeDisplayNames"))
    }
}

extension Trains.LinterSettingsImpl: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PklCodingKey.self)

        try container.encode(projectIdPrefix, forKey: PklCodingKey(string: "projectIdPrefix"))
        try container.encode(projectIdRegexes, forKey: PklCodingKey(string: "projectIdRegexes"))
        try container.encode(maxSubjectLength, forKey: PklCodingKey(string: "maxSubjectLength"))
        try container.encode(maxBodyLineLength, forKey: PklCodingKey(string: "maxBodyLineLength"))
        try container.encode(requireCommitTypes, forKey: PklCodingKey(string: "requireCommitTypes"))
        try container.encode(projectIdsInBranches.rawValue, forKey: PklCodingKey(string: "projectIdsInBranches"))
    }
}

extension Trains.PipelinePropertiesImpl: Encodable {
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: PklCodingKey.self)

        try container.encode(jobId, forKey: PklCodingKey(string: "jobId"))
        try container.encode(refSlug, forKey: PklCodingKey(string: "refSlug"))
        try container.encode(refName, forKey: PklCodingKey(string: "refName"))
        try container.encode(tagName, forKey: PklCodingKey(string: "tagName"))
        try container.encode(pagesUrl, forKey: PklCodingKey(string: "pagesUrl"))
        try container.encode(eventType, forKey: PklCodingKey(string: "eventType"))
        try container.encode(pipelineId, forKey: PklCodingKey(string: "pipelineId"))
        try container.encode(defaultBranch, forKey: PklCodingKey(string: "defaultBranch"))

        try container.encode(userProperties, forKey: PklCodingKey(string: "userProperties"))
    }
}

extension Trains.BuildSettingsImpl: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PklCodingKey.self)

        try container.encode(scheme, forKey: PklCodingKey(string: "scheme"))
        try container.encode(teamId, forKey: PklCodingKey(string: "teamId"))
        try container.encode(teamName, forKey: PklCodingKey(string: "teamName"))
        try container.encode(platform, forKey: PklCodingKey(string: "platform"))
        try container.encode(xcodeproj, forKey: PklCodingKey(string: "xcodeproj"))
        try container.encode(productName, forKey: PklCodingKey(string: "productName"))
        try container.encode(appIdentifier, forKey: PklCodingKey(string: "appIdentifier"))
        try container.encode(announceForum, forKey: PklCodingKey(string: "announceForum"))
        try container.encode(dmgConfigPath, forKey: PklCodingKey(string: "dmgConfigPath"))
        try container.encode(userProperties, forKey: PklCodingKey(string: "userProperties"))
        try container.encode(outputDirectory, forKey: PklCodingKey(string: "outputDirectory"))
        try container.encode(testplansDirectory, forKey: PklCodingKey(string: "testplansDirectory"))

        if let ci = self.ci as? Trains.PipelinePropertiesImpl {
            try container.encode(ci, forKey: PklCodingKey(string: "ci"))
        }

        if let match = self.match as? Trains.MatchSettingsImpl {
            try container.encode(match, forKey: PklCodingKey(string: "match"))
        }
    }
}

extension Trains.MatchSettingsImpl: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PklCodingKey.self)

        try container.encode(branchName, forKey: PklCodingKey(string: "branchName"))
        try container.encode(keychainName, forKey: PklCodingKey(string: "keychainName"))
    }
}

extension Trains.TrailersImpl: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PklCodingKey.self)
        
        try container.encode(projectId, forKey: PklCodingKey(string: "projectId"))
        try container.encode(mergeRequest, forKey: PklCodingKey(string: "mergeRequest"))
        try container.encode(releasePipeline, forKey: PklCodingKey(string: "releasePipeline"))
        try container.encode(failedPipeline, forKey: PklCodingKey(string: "failedPipeline"))
        try container.encode(releaseImmediately, forKey: PklCodingKey(string: "releaseImmediately"))
        try container.encode(automaticReleaseDate, forKey: PklCodingKey(string: "automaticReleaseDate"))
    }
}

extension Trains.SparkleImpl: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PklCodingKey.self)
        
        try container.encode(announceForum, forKey: PklCodingKey(string: "announceForum"))
        try container.encode(appcastChannel, forKey: PklCodingKey(string: "appcastChannel"))
        try container.encode(userProperties, forKey: PklCodingKey(string: "userProperties"))
        try container.encode(maximumSystemVersion, forKey: PklCodingKey(string: "maximumSystemVersion"))
        try container.encode(minimumSystemVersion, forKey: PklCodingKey(string: "minimumSystemVersion"))
        try container.encode(phasedRolloutInterval, forKey: PklCodingKey(string: "phasedRolloutInterval"))
    }
}

extension Trains.AppStoreImpl: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PklCodingKey.self)

        try container.encode(action.rawValue, forKey: PklCodingKey(string: "action"))
        try container.encode(announceForum, forKey: PklCodingKey(string: "announceForum"))
        try container.encode(userProperties, forKey: PklCodingKey(string: "userProperties"))
        try container.encode(testflightGroup, forKey: PklCodingKey(string: "testflightGroup"))
    }
}

extension Trains.CustomDistributionImpl: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PklCodingKey.self)

        try container.encode(exportMethod, forKey: PklCodingKey(string: "exportMethod"))
        try container.encode(userProperties, forKey: PklCodingKey(string: "userProperties"))
    }
}
