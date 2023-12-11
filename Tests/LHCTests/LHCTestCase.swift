//
//  LHCTestCase.swift
//  
//
//  Created by John Biggs on 13.10.23.
//

import Foundation
import XCTest

@testable import LHC
@testable import LHCInternal
@testable import git_lhc

class LHCTestCase: XCTestCase {
    static let homePath = "/Users/test"
    static let repoPath = "\(homePath)/repo"
    static let configPath = "\(repoPath)/.lhc"

    var repoUnderTest: MockRepository = .mock

    var testOutput: String {
        let printer = Internal.printer as! MockPrinter
        return printer.printedItems.filter { !$0.error }
            .map(\.0)
            .joined()
    }

    var errorOutput: String {
        let printer = Internal.printer as! MockPrinter
        return printer.printedItems.filter(\.error)
            .map(\.0)
            .joined()
    }

    override func invokeTest() {
        let printer = Internal.printer
        let openRepo = Internal.openRepo
        let mockRepo = MockRepository.mock
        let repoUpdated = MockRepository.repoUpdated
        let oldFileManager = Internal.fileManager
        let getConfig = Configuration.getConfig
        let readPassphrase = Internal.readPassphrase
        let promptUser = Internal.promptUser
        let processInfo = Internal.processInfo
        let jiraClient = Internal.jiraClient
        let isInteractive = Internal.isInteractiveSession

        Internal.processInfo = MockProcessInfo.mock
        Internal.jiraClient = MockJiraClient.mock
        Internal.isInteractiveSession = { true }

        var fileManager = MockFileManager.mock
        fileManager.currentDirectoryPath = Self.repoPath
        fileManager.homeDirectoryForCurrentUser = URL(string: Self.homePath)!

        Internal.fileManager = fileManager

        Internal.openRepo = { url in
            XCTAssertEqual((url.path() as NSString).standardizingPath, Self.repoPath)
            return .success(MockRepository.mock)
        }

        Internal.readPassphrase = { _ in
            return "foo bar"
        }

        Internal.promptUser = { _ in
            return "y"
        }

        Internal.spawnProcessAndWaitForTermination = { _, _, _, _, _, _ in }

        Internal.printer = MockPrinter.mock

        MockRepository.repoUpdated = { [weak self] in
            self?.repoUnderTest = $0
        }

        super.invokeTest()

        Configuration.getConfig = getConfig
        Internal.fileManager = oldFileManager
        MockRepository.mock = mockRepo
        MockRepository.repoUpdated = repoUpdated
        Internal.openRepo = openRepo
        Internal.printer = printer
        Internal.readPassphrase = readPassphrase
        Internal.promptUser = promptUser
        Internal.processInfo = processInfo
        Internal.jiraClient = jiraClient
        Internal.isInteractiveSession = isInteractive
    }

    func setEnv<E: EnvironmentVariable>(_ env: E, to value: String) {
        Internal.processInfo = ((Internal.processInfo as? MockProcessInfo) ?? .mock)
            .with(envVar: env, setTo: value)
    }

    func setBranch(_ branch: MockBranch) throws {
        try MockRepository.mock.setHEAD(branch.oid)
        setEnv(GitlabEnvironment.commitBranch, to: branch.name)
    }
}
