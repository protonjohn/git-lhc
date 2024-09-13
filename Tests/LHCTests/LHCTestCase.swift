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
        let shell = Internal.shell as! MockShell
        return shell.printedItems.filter { !$0.error }
            .map(\.0)
            .joined()
    }

    var errorOutput: String {
        let shell = Internal.shell as! MockShell
        return shell.printedItems.filter(\.error)
            .map(\.0)
            .joined()
    }

    override func invokeTest() {
        let shell = Internal.shell
        let openRepo = Internal.openRepo
        let mockRepo = MockRepository.mock
        let repoUpdated = MockRepository.repoUpdated
        let oldFileManager = Internal.fileManager
        let oldLoadTrains = Internal.loadTrains
        let promptUser = Internal.promptUser
        let processInfo = Internal.processInfo
        let isInteractive = Internal.isInteractiveSession
        let registerTransports = Internal.registerTransports

        Internal.processInfo = MockProcessInfo.mock
        Internal.isInteractiveSession = { true }

        var fileManager = MockFileManager.mock
        fileManager.currentDirectoryPath = Self.repoPath
        fileManager.homeDirectoryForCurrentUser = URL(string: Self.homePath)!

        Internal.fileManager = fileManager

        Internal.openRepo = { url in
            XCTAssertEqual((url.path(percentEncoded: false) as NSString).standardizingPath, Self.repoPath)
            return .success(MockRepository.mock)
        }

        Internal.loadTrains = { _ in
            [Trains.TrainImpl(testName: "test", tagPrefix: nil)]
        }

        Internal.registerTransports = {
            
        }

        Internal.promptUser = { prompt in
            // We don't want to edit files, but otherwise we want to approve everything.
            if prompt == "Edit? (y/N) " {
                return "n"
            }
            return "y"
        }

        Internal.shell = MockShell.mock

        MockRepository.repoUpdated = { [weak self] in
            self?.repoUnderTest = $0
        }

        super.invokeTest()

        Internal.fileManager = oldFileManager
        MockRepository.mock = mockRepo
        MockRepository.repoUpdated = repoUpdated
        Internal.loadTrains = oldLoadTrains
        Internal.openRepo = openRepo
        Internal.shell = shell
        Internal.promptUser = promptUser
        Internal.processInfo = processInfo
        Internal.isInteractiveSession = isInteractive
        Internal.registerTransports = registerTransports
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
