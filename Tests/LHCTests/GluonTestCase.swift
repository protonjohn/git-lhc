//
//  LHCTestCase.swift
//  
//
//  Created by John Biggs on 13.10.23.
//

import Foundation
import XCTest

@testable import git_lhc

class LHCTestCase: XCTestCase {
    static let homePath = "/Users/test"
    static let repoPath = "\(homePath)/repo"
    static let configPath = "\(repoPath)/.gluon.yml"

    var repoUnderTest: MockRepository = .mock

    var testOutput: String {
        let printer = LHC.printer as! MockPrinter
        return printer.printedItems.filter { !$0.error }
            .map(\.0)
            .joined()
    }

    var errorOutput: String {
        let printer = LHC.printer as! MockPrinter
        return printer.printedItems.filter(\.error)
            .map(\.0)
            .joined()
    }

    override func invokeTest() {
        let printer = LHC.printer
        let openRepo = LHC.openRepo
        let mockRepo = MockRepository.mock
        let repoUpdated = MockRepository.repoUpdated
        let oldFileManager = LHC.fileManager
        let config = Configuration.configuration
        let readPassphrase = LHC.readPassphrase
        let promptUser = LHC.promptUser
        let processInfo = LHC.processInfo
        let jiraClient = LHC.jiraClient
        let isInteractive = LHC.isInteractiveSession

        LHC.processInfo = MockProcessInfo.mock
        LHC.jiraClient = MockJiraClient.mock
        LHC.isInteractiveSession = { true }

        var fileManager = MockFileManager.mock
        fileManager.currentDirectoryPath = Self.repoPath
        fileManager.homeDirectoryForCurrentUser = URL(string: Self.homePath)!

        LHC.fileManager = fileManager

        LHC.openRepo = { url in
            XCTAssertEqual((url.path() as NSString).standardizingPath, Self.repoPath)
            return .success(MockRepository.mock)
        }

        LHC.readPassphrase = { _ in
            return "foo bar"
        }

        LHC.promptUser = { _ in
            return "y"
        }

        LHC.spawnProcessAndWaitForTermination = { _, _ in }

        LHC.printer = MockPrinter.mock

        MockRepository.repoUpdated = { [weak self] in
            self?.repoUnderTest = $0
        }

        super.invokeTest()

        Configuration.configuration = config
        LHC.fileManager = oldFileManager
        MockRepository.mock = mockRepo
        MockRepository.repoUpdated = repoUpdated
        LHC.openRepo = openRepo
        LHC.printer = printer
        LHC.readPassphrase = readPassphrase
        LHC.promptUser = promptUser
        LHC.processInfo = processInfo
        LHC.jiraClient = jiraClient
        LHC.isInteractiveSession = isInteractive
    }

    func setEnv<E: EnvironmentVariable>(_ env: E, to value: String) {
        LHC.processInfo = ((LHC.processInfo as? MockProcessInfo) ?? .mock)
            .with(envVar: env, setTo: value)
    }

    func setBranch(_ branch: MockBranch) throws {
        try MockRepository.mock.setHEAD(branch.oid)
        setEnv(GitlabEnvironment.commitBranch, to: branch.name)
    }
}
