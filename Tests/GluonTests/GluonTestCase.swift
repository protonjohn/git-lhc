//
//  GluonTestCase.swift
//  
//
//  Created by John Biggs on 13.10.23.
//

import Foundation
import XCTest

@testable import gluon

class GluonTestCase: XCTestCase {
    static let homePath = "/Users/test"
    static let repoPath = "\(homePath)/repo"
    static let configPath = "\(repoPath)/.gluon.yml"

    var repoUnderTest: MockRepository = .mock

    var testOutput: String {
        let printer = Gluon.printer as! MockPrinter
        return printer.printedItems.filter { !$0.error }
            .map(\.0)
            .joined()
    }

    var errorOutput: String {
        let printer = Gluon.printer as! MockPrinter
        return printer.printedItems.filter(\.error)
            .map(\.0)
            .joined()
    }

    override func invokeTest() {
        let printer = Gluon.printer
        let openRepo = Gluon.openRepo
        let mockRepo = MockRepository.mock
        let repoUpdated = MockRepository.repoUpdated
        let oldFileManager = Gluon.fileManager
        let config = Configuration.configuration
        let readPassphrase = Gluon.readPassphrase
        let promptUser = Gluon.promptUser
        let processInfo = Gluon.processInfo

        Gluon.processInfo = MockProcessInfo.mock

        var fileManager = MockFileManager.mock
        fileManager.currentDirectoryPath = Self.repoPath
        fileManager.homeDirectoryForCurrentUser = URL(string: Self.homePath)!

        Gluon.fileManager = fileManager

        Gluon.openRepo = { url in
            XCTAssertEqual(url.path(), Self.repoPath)
            return .success(MockRepository.mock)
        }

        Gluon.readPassphrase = {
            return "foo bar"
        }

        Gluon.promptUser = { _ in
            return "y"
        }

        Gluon.printer = MockPrinter.mock

        MockRepository.repoUpdated = { [weak self] in
            self?.repoUnderTest = $0
        }

        super.invokeTest()

        Configuration.configuration = config
        Gluon.fileManager = oldFileManager
        MockRepository.mock = mockRepo
        MockRepository.repoUpdated = repoUpdated
        Gluon.openRepo = openRepo
        Gluon.printer = printer
        Gluon.readPassphrase = readPassphrase
        Gluon.promptUser = promptUser
        Gluon.processInfo = processInfo
    }

    func setEnv<E: EnvironmentVariable>(_ env: E, to value: String) {
        Gluon.processInfo = ((Gluon.processInfo as? MockProcessInfo) ?? .mock)
            .with(envVar: env, setTo: value)
    }

    func setBranch(_ branch: MockBranch) throws {
        try MockRepository.mock.setHEAD(branch.oid)
        setEnv(GitlabEnvironment.commitBranch, to: branch.name)
    }
}
