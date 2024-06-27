// Code generated from Pkl module `Trains`. DO NOT EDIT.
import PklSwift

public enum Trains {}

public protocol Trains_Module: PklRegisteredType, DynamicallyEquatable, Hashable {
    var properties: any Trains.Properties { get }

    var trains: [any Trains.Train] { get }
}

public protocol Trains_Properties: PklRegisteredType, DynamicallyEquatable, Hashable {
    var ci: Bool { get }

    var pipelineIdentifier: String? { get }

    var channel: Trains.ReleaseChannel { get }

    var checklist: String? { get }
}

public protocol Trains_Train: PklRegisteredType, DynamicallyEquatable, Hashable {
    var name: String { get }

    var displayName: String? { get }

    var tagPrefix: String? { get }

    var releaseChannel: Trains.ReleaseChannel { get }

    var attrsRef: String { get }

    var checklistsRef: String { get }

    var templatesDirectory: String? { get }

    var checklistDirectory: String? { get }

    var versionBumps: [String: Trains.VersionBump] { get }

    var linter: any Trains.LinterSettings { get }

    var build: (any Trains.BuildSettings)? { get }

    var distribution: Trains.DistributionSettings? { get }

    var trailers: any Trains.Trailers { get }

    var changelogExcludedTypes: [String]? { get }

    var changelogTypeDisplayNames: [String: String]? { get }
}

public protocol Trains_LinterSettings: PklRegisteredType, DynamicallyEquatable, Hashable {
    var projectIdPrefix: String? { get }

    var maxSubjectLength: Int? { get }

    var maxBodyLineLength: Int? { get }

    var projectIdRegexes: [String] { get }

    var projectIdsInBranches: Trains.LintProjectIdsInBranches { get }

    var requireCommitTypes: [String]? { get }
}

public protocol Trains_BuildSettings: PklRegisteredType, DynamicallyEquatable, Hashable {
    var ci: Bool { get }

    var pipelineIdentifier: String? { get }

    var scheme: String? { get }

    var teamId: String? { get }

    var teamName: String? { get }

    var platform: String? { get }

    var xcodeproj: String? { get }

    var productName: String? { get }

    var appIdentifier: String? { get }

    var outputDirectory: String? { get }

    var testplansDirectory: String? { get }

    var announceChannel: String? { get }

    var match: (any Trains.MatchSettings)? { get }
}

public protocol Trains_MatchSettings: PklRegisteredType, DynamicallyEquatable, Hashable {
    var branchName: String? { get }

    var keychainName: String? { get }
}

public protocol Trains_Trailers: PklRegisteredType, DynamicallyEquatable, Hashable {
    var projectId: String { get }

    var releasePipeline: String { get }

    var failedPipeline: String { get }

    var automaticReleaseDate: String { get }

    var releaseImmediately: String { get }

    var mergeRequest: String { get }
}

public protocol Trains_Sparkle: PklRegisteredType, DynamicallyEquatable, Hashable {
    var releaseChannel: String? { get }

    var announceChannel: String? { get }

    var dmgConfig: String? { get }
}

public protocol Trains_AppStore: PklRegisteredType, DynamicallyEquatable, Hashable {
    var action: Trains.AppStoreAction { get }

    var testflightGroup: String? { get }

    var announceChannel: String? { get }
}

public protocol Trains_CustomDistribution: PklRegisteredType, DynamicallyEquatable, Hashable {
    var exportMethod: String? { get }
}

extension Trains {
    public enum ReleaseChannel: String, CaseIterable, Decodable, Hashable {
        case alpha = "alpha"
        case beta = "beta"
        case rc = "rc"
        case production = "production"
    }

    public enum VersionBump: String, CaseIterable, Decodable, Hashable {
        case major = "Major"
        case minor = "Minor"
        case patch = "Patch"
    }

    public enum LintProjectIdsInBranches: String, CaseIterable, Decodable, Hashable {
        case never = "Never"
        case always = "Always"
        case commitsMustMatch = "CommitsMustMatch"
    }

    public enum DistributionSettings: Decodable, Hashable {
        case sparkle(any Sparkle)
        case appStore(any AppStore)
        case customDistribution(any CustomDistribution)

        public static func ==(lhs: DistributionSettings, rhs: DistributionSettings) -> Bool {
            switch (lhs, rhs) {
            case let (.sparkle(a), .sparkle(b)):
                return a.isDynamicallyEqual(to: b)
            case let (.appStore(a), .appStore(b)):
                return a.isDynamicallyEqual(to: b)
            case let (.customDistribution(a), .customDistribution(b)):
                return a.isDynamicallyEqual(to: b)
            default:
                return false
            }
        }

        public init(from decoder: Decoder) throws {
            let decoded = try decoder.singleValueContainer().decode(PklSwift.PklAny.self).value
            switch decoded {
            case let decoded as any Sparkle:
                self = DistributionSettings.sparkle(decoded)
            case let decoded as any AppStore:
                self = DistributionSettings.appStore(decoded)
            case let decoded as any CustomDistribution:
                self = DistributionSettings.customDistribution(decoded)
            default:
                throw DecodingError.typeMismatch(
                    DistributionSettings.self,
                    .init(
                        codingPath: decoder.codingPath,
                        debugDescription: "Expected type DistributionSettings, but got \(String(describing: decoded))"
                    )
                )
            }
        }

        public func hash(into hasher: inout Hasher) {
            switch self {
            case let .sparkle(value):
                hasher.combine(value)
            case let .appStore(value):
                hasher.combine(value)
            case let .customDistribution(value):
                hasher.combine(value)
            }
        }
    }

    /// The type of action to do when interacting with App Store Connect.
    ///
    /// The "Upload" action uploads a new build and publishes it to TestFlight.
    /// The "Promote" action takes an existing build with the same number, and adds it to another testing group.
    /// The "Submit" action takes an existing build with the same number, and submits it for app review.
    public enum AppStoreAction: String, CaseIterable, Decodable, Hashable {
        case upload = "Upload"
        case promote = "Promote"
        case submit = "Submit"
    }

    public typealias Module = Trains_Module

    public struct ModuleImpl: Module {
        public static var registeredIdentifier: String = "Trains"

        public var properties: any Properties

        public var trains: [any Train]

        public init(properties: any Properties, trains: [any Train]) {
            self.properties = properties
            self.trains = trains
        }

        public static func ==(lhs: ModuleImpl, rhs: ModuleImpl) -> Bool {
            lhs.properties.isDynamicallyEqual(to: rhs.properties)
            && arrayEquals(arr1: lhs.trains, arr2: rhs.trains)
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(properties)
            for x in self.trains {
                hasher.combine(x)
            }
        }

        public init(from decoder: Decoder) throws {
            let dec = try decoder.container(keyedBy: PklCodingKey.self)
            let properties = try dec.decode(PklSwift.PklAny.self, forKey: PklCodingKey(string: "properties"))
                    .value as! any Properties
            let trains = try dec.decode([PklSwift.PklAny].self, forKey: PklCodingKey(string: "trains"))
                    .map { $0.value as! any Train }
            self = ModuleImpl(properties: properties, trains: trains)
        }
    }

    public typealias Properties = Trains_Properties

    /// Top-level properties read from configuration input.
    ///
    /// These properties are defined by LHC when evaluating the configuration file, and can be cased on
    /// to provide different values depending on the environment or release channel.
    public struct PropertiesImpl: Properties {
        public static var registeredIdentifier: String = "Trains#Properties"

        public var ci: Bool

        public var pipelineIdentifier: String?

        public var channel: ReleaseChannel

        public var checklist: String?

        public init(
            ci: Bool,
            pipelineIdentifier: String?,
            channel: ReleaseChannel,
            checklist: String?
        ) {
            self.ci = ci
            self.pipelineIdentifier = pipelineIdentifier
            self.channel = channel
            self.checklist = checklist
        }
    }

    public typealias Train = Trains_Train

    public struct TrainImpl: Train {
        public static var registeredIdentifier: String = "Trains#Train"

        public var name: String

        public var displayName: String?

        public var tagPrefix: String?

        public var releaseChannel: ReleaseChannel

        public var attrsRef: String

        public var checklistsRef: String

        public var templatesDirectory: String?

        public var checklistDirectory: String?

        public var versionBumps: [String: VersionBump]

        public var linter: any LinterSettings

        public var build: (any BuildSettings)?

        public var distribution: DistributionSettings?

        public var trailers: any Trailers

        public var changelogExcludedTypes: [String]?

        public var changelogTypeDisplayNames: [String: String]?

        public init(
            name: String,
            displayName: String?,
            tagPrefix: String?,
            releaseChannel: ReleaseChannel,
            attrsRef: String,
            checklistsRef: String,
            templatesDirectory: String?,
            checklistDirectory: String?,
            versionBumps: [String: VersionBump],
            linter: any LinterSettings,
            build: (any BuildSettings)?,
            distribution: DistributionSettings?,
            trailers: any Trailers,
            changelogExcludedTypes: [String]?,
            changelogTypeDisplayNames: [String: String]?
        ) {
            self.name = name
            self.displayName = displayName
            self.tagPrefix = tagPrefix
            self.releaseChannel = releaseChannel
            self.attrsRef = attrsRef
            self.checklistsRef = checklistsRef
            self.templatesDirectory = templatesDirectory
            self.checklistDirectory = checklistDirectory
            self.versionBumps = versionBumps
            self.linter = linter
            self.build = build
            self.distribution = distribution
            self.trailers = trailers
            self.changelogExcludedTypes = changelogExcludedTypes
            self.changelogTypeDisplayNames = changelogTypeDisplayNames
        }

        public static func ==(lhs: TrainImpl, rhs: TrainImpl) -> Bool {
            lhs.name == rhs.name
            && lhs.displayName == rhs.displayName
            && lhs.tagPrefix == rhs.tagPrefix
            && lhs.releaseChannel == rhs.releaseChannel
            && lhs.attrsRef == rhs.attrsRef
            && lhs.checklistsRef == rhs.checklistsRef
            && lhs.templatesDirectory == rhs.templatesDirectory
            && lhs.checklistDirectory == rhs.checklistDirectory
            && lhs.versionBumps == rhs.versionBumps
            && lhs.linter.isDynamicallyEqual(to: rhs.linter)
            && ((lhs.build == nil && rhs.build == nil) || lhs.build?.isDynamicallyEqual(to: rhs.build) ?? false)
            && lhs.distribution == rhs.distribution
            && lhs.trailers.isDynamicallyEqual(to: rhs.trailers)
            && lhs.changelogExcludedTypes == rhs.changelogExcludedTypes
            && lhs.changelogTypeDisplayNames == rhs.changelogTypeDisplayNames
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(name)
            hasher.combine(displayName)
            hasher.combine(tagPrefix)
            hasher.combine(releaseChannel)
            hasher.combine(attrsRef)
            hasher.combine(checklistsRef)
            hasher.combine(templatesDirectory)
            hasher.combine(checklistDirectory)
            hasher.combine(versionBumps)
            hasher.combine(linter)
            if let build {
                hasher.combine(build)
            }
            hasher.combine(distribution)
            hasher.combine(trailers)
            hasher.combine(changelogExcludedTypes)
            hasher.combine(changelogTypeDisplayNames)
        }

        public init(from decoder: Decoder) throws {
            let dec = try decoder.container(keyedBy: PklCodingKey.self)
            let name = try dec.decode(String.self, forKey: PklCodingKey(string: "name"))
            let displayName = try dec.decode(String?.self, forKey: PklCodingKey(string: "displayName"))
            let tagPrefix = try dec.decode(String?.self, forKey: PklCodingKey(string: "tagPrefix"))
            let releaseChannel = try dec.decode(ReleaseChannel.self, forKey: PklCodingKey(string: "releaseChannel"))
            let attrsRef = try dec.decode(String.self, forKey: PklCodingKey(string: "attrsRef"))
            let checklistsRef = try dec.decode(String.self, forKey: PklCodingKey(string: "checklistsRef"))
            let templatesDirectory = try dec.decode(String?.self, forKey: PklCodingKey(string: "templatesDirectory"))
            let checklistDirectory = try dec.decode(String?.self, forKey: PklCodingKey(string: "checklistDirectory"))
            let versionBumps = try dec.decode([String: VersionBump].self, forKey: PklCodingKey(string: "versionBumps"))
            let linter = try dec.decode(PklSwift.PklAny.self, forKey: PklCodingKey(string: "linter"))
                    .value as! any LinterSettings
            let build = try dec.decode(PklSwift.PklAny.self, forKey: PklCodingKey(string: "build"))
                    .value as! (any BuildSettings)?
            let distribution = try dec.decode(DistributionSettings?.self, forKey: PklCodingKey(string: "distribution"))
            let trailers = try dec.decode(PklSwift.PklAny.self, forKey: PklCodingKey(string: "trailers"))
                    .value as! any Trailers
            let changelogExcludedTypes = try dec.decode([String]?.self, forKey: PklCodingKey(string: "changelogExcludedTypes"))
            let changelogTypeDisplayNames = try dec.decode([String: String]?.self, forKey: PklCodingKey(string: "changelogTypeDisplayNames"))
            self = TrainImpl(name: name, displayName: displayName, tagPrefix: tagPrefix, releaseChannel: releaseChannel, attrsRef: attrsRef, checklistsRef: checklistsRef, templatesDirectory: templatesDirectory, checklistDirectory: checklistDirectory, versionBumps: versionBumps, linter: linter, build: build, distribution: distribution, trailers: trailers, changelogExcludedTypes: changelogExcludedTypes, changelogTypeDisplayNames: changelogTypeDisplayNames)
        }
    }

    public typealias LinterSettings = Trains_LinterSettings

    public struct LinterSettingsImpl: LinterSettings {
        public static var registeredIdentifier: String = "Trains#LinterSettings"

        /// The prefix to use for a ticket item ID, if any.
        ///
        /// For example, if using Jira, the project ID prefix might be `EXAMPLE-`.
        public var projectIdPrefix: String?

        public var maxSubjectLength: Int?

        public var maxBodyLineLength: Int?

        public var projectIdRegexes: [String]

        public var projectIdsInBranches: LintProjectIdsInBranches

        /// The default conventional commit types allowed for the project.
        ///
        /// If left set to `null`, then the linter will not reject any commits based on an unknown type.
        public var requireCommitTypes: [String]?

        public init(
            projectIdPrefix: String?,
            maxSubjectLength: Int?,
            maxBodyLineLength: Int?,
            projectIdRegexes: [String],
            projectIdsInBranches: LintProjectIdsInBranches,
            requireCommitTypes: [String]?
        ) {
            self.projectIdPrefix = projectIdPrefix
            self.maxSubjectLength = maxSubjectLength
            self.maxBodyLineLength = maxBodyLineLength
            self.projectIdRegexes = projectIdRegexes
            self.projectIdsInBranches = projectIdsInBranches
            self.requireCommitTypes = requireCommitTypes
        }
    }

    public typealias BuildSettings = Trains_BuildSettings

    /// Settings for building the project.
    public struct BuildSettingsImpl: BuildSettings {
        public static var registeredIdentifier: String = "Trains#BuildSettings"

        /// Whether or not the current build is being invoked from a CI context.
        public var ci: Bool

        /// A unique string identifying the current CI pipeline, if any.
        public var pipelineIdentifier: String?

        /// The scheme to use in the Xcode project.
        public var scheme: String?

        /// The team ID to use for signing.
        public var teamId: String?

        /// The team name which corresponds to the given team ID.
        public var teamName: String?

        /// The platform to build for (e.g., iOS, macOS, tvOS).
        public var platform: String?

        /// The path to the Xcode project .xcodeproj file.
        public var xcodeproj: String?

        /// The name of the product, usually the name of the app bundle.
        public var productName: String?

        /// The bundle identifier of the application.
        public var appIdentifier: String?

        /// The output directory to place files in.
        public var outputDirectory: String?

        /// Where to find the test plans in the project.
        public var testplansDirectory: String?

        /// The slack channel to announce any new builds in.
        public var announceChannel: String?

        /// Settings for use with fastlane match.
        public var match: (any MatchSettings)?

        public init(
            ci: Bool,
            pipelineIdentifier: String?,
            scheme: String?,
            teamId: String?,
            teamName: String?,
            platform: String?,
            xcodeproj: String?,
            productName: String?,
            appIdentifier: String?,
            outputDirectory: String?,
            testplansDirectory: String?,
            announceChannel: String?,
            match: (any MatchSettings)?
        ) {
            self.ci = ci
            self.pipelineIdentifier = pipelineIdentifier
            self.scheme = scheme
            self.teamId = teamId
            self.teamName = teamName
            self.platform = platform
            self.xcodeproj = xcodeproj
            self.productName = productName
            self.appIdentifier = appIdentifier
            self.outputDirectory = outputDirectory
            self.testplansDirectory = testplansDirectory
            self.announceChannel = announceChannel
            self.match = match
        }

        public static func ==(lhs: BuildSettingsImpl, rhs: BuildSettingsImpl) -> Bool {
            lhs.ci == rhs.ci
            && lhs.pipelineIdentifier == rhs.pipelineIdentifier
            && lhs.scheme == rhs.scheme
            && lhs.teamId == rhs.teamId
            && lhs.teamName == rhs.teamName
            && lhs.platform == rhs.platform
            && lhs.xcodeproj == rhs.xcodeproj
            && lhs.productName == rhs.productName
            && lhs.appIdentifier == rhs.appIdentifier
            && lhs.outputDirectory == rhs.outputDirectory
            && lhs.testplansDirectory == rhs.testplansDirectory
            && lhs.announceChannel == rhs.announceChannel
            && ((lhs.match == nil && rhs.match == nil) || lhs.match?.isDynamicallyEqual(to: rhs.match) ?? false)
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(ci)
            hasher.combine(pipelineIdentifier)
            hasher.combine(scheme)
            hasher.combine(teamId)
            hasher.combine(teamName)
            hasher.combine(platform)
            hasher.combine(xcodeproj)
            hasher.combine(productName)
            hasher.combine(appIdentifier)
            hasher.combine(outputDirectory)
            hasher.combine(testplansDirectory)
            hasher.combine(announceChannel)
            if let match {
                hasher.combine(match)
            }
        }

        public init(from decoder: Decoder) throws {
            let dec = try decoder.container(keyedBy: PklCodingKey.self)
            let ci = try dec.decode(Bool.self, forKey: PklCodingKey(string: "ci"))
            let pipelineIdentifier = try dec.decode(String?.self, forKey: PklCodingKey(string: "pipelineIdentifier"))
            let scheme = try dec.decode(String?.self, forKey: PklCodingKey(string: "scheme"))
            let teamId = try dec.decode(String?.self, forKey: PklCodingKey(string: "teamId"))
            let teamName = try dec.decode(String?.self, forKey: PklCodingKey(string: "teamName"))
            let platform = try dec.decode(String?.self, forKey: PklCodingKey(string: "platform"))
            let xcodeproj = try dec.decode(String?.self, forKey: PklCodingKey(string: "xcodeproj"))
            let productName = try dec.decode(String?.self, forKey: PklCodingKey(string: "productName"))
            let appIdentifier = try dec.decode(String?.self, forKey: PklCodingKey(string: "appIdentifier"))
            let outputDirectory = try dec.decode(String?.self, forKey: PklCodingKey(string: "outputDirectory"))
            let testplansDirectory = try dec.decode(String?.self, forKey: PklCodingKey(string: "testplansDirectory"))
            let announceChannel = try dec.decode(String?.self, forKey: PklCodingKey(string: "announceChannel"))
            let match = try dec.decode(PklSwift.PklAny.self, forKey: PklCodingKey(string: "match"))
                    .value as! (any MatchSettings)?
            self = BuildSettingsImpl(ci: ci, pipelineIdentifier: pipelineIdentifier, scheme: scheme, teamId: teamId, teamName: teamName, platform: platform, xcodeproj: xcodeproj, productName: productName, appIdentifier: appIdentifier, outputDirectory: outputDirectory, testplansDirectory: testplansDirectory, announceChannel: announceChannel, match: match)
        }
    }

    public typealias MatchSettings = Trains_MatchSettings

    public struct MatchSettingsImpl: MatchSettings {
        public static var registeredIdentifier: String = "Trains#MatchSettings"

        public var branchName: String?

        public var keychainName: String?

        public init(branchName: String?, keychainName: String?) {
            self.branchName = branchName
            self.keychainName = keychainName
        }
    }

    public typealias Trailers = Trains_Trailers

    public struct TrailersImpl: Trailers {
        public static var registeredIdentifier: String = "Trains#Trailers"

        public var projectId: String

        public var releasePipeline: String

        public var failedPipeline: String

        public var automaticReleaseDate: String

        public var releaseImmediately: String

        public var mergeRequest: String

        public init(
            projectId: String,
            releasePipeline: String,
            failedPipeline: String,
            automaticReleaseDate: String,
            releaseImmediately: String,
            mergeRequest: String
        ) {
            self.projectId = projectId
            self.releasePipeline = releasePipeline
            self.failedPipeline = failedPipeline
            self.automaticReleaseDate = automaticReleaseDate
            self.releaseImmediately = releaseImmediately
            self.mergeRequest = mergeRequest
        }
    }

    public typealias Sparkle = Trains_Sparkle

    /// Settings to control app distribution via the Sparkle framework.
    public struct SparkleImpl: Sparkle {
        public static var registeredIdentifier: String = "Trains#Sparkle"

        /// The release channel to specify in the sparkle xml file.
        ///
        /// More details can be found [here](https://sparkle-project.org/documentation/publishing/#channels).
        public var releaseChannel: String?

        /// The Slack channel in which to announce the new release.
        public var announceChannel: String?

        /// The path to the dmg configuration file (used by the `dmgbuild` Python utility).
        ///
        /// This is most applicable to the macOS platform when distributing via Sparkle updates.
        public var dmgConfig: String?

        public init(releaseChannel: String?, announceChannel: String?, dmgConfig: String?) {
            self.releaseChannel = releaseChannel
            self.announceChannel = announceChannel
            self.dmgConfig = dmgConfig
        }
    }

    public typealias AppStore = Trains_AppStore

    /// Settings to control app distribution on the App Store.
    public struct AppStoreImpl: AppStore {
        public static var registeredIdentifier: String = "Trains#AppStore"

        public var action: AppStoreAction

        /// The TestFlight group to use for the given App Store action.
        ///
        /// If `action` is "Submit," then this value has no effect.
        public var testflightGroup: String?

        /// The Slack channel in which to announce the new release.
        public var announceChannel: String?

        public init(action: AppStoreAction, testflightGroup: String?, announceChannel: String?) {
            self.action = action
            self.testflightGroup = testflightGroup
            self.announceChannel = announceChannel
        }
    }

    public typealias CustomDistribution = Trains_CustomDistribution

    public struct CustomDistributionImpl: CustomDistribution {
        public static var registeredIdentifier: String = "Trains#CustomDistribution"

        public var exportMethod: String?

        public init(exportMethod: String?) {
            self.exportMethod = exportMethod
        }
    }
}