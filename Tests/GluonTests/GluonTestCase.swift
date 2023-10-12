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
    let configPath = "/Users/test/repo/.gluon.yml"
    let repoPath = "/Users/test/repo"

    var testOutput: String {
        let printer = Gluon.printer as! MockPrinter
        return printer.printedItems.filter { $0.stream == nil }
            .map(\.0)
            .joined()
    }

    var errorOutput: String {
        let printer = Gluon.printer as! MockPrinter
        return printer.printedItems.filter { $0.stream != nil }
            .map(\.0)
            .joined()
    }
    
    override func setUp() {
        Gluon.processInfo = MockProcessInfo.mock

        var fileManager = MockFileManager.mock
        fileManager.currentDirectoryPath = repoPath

        Gluon.fileManager = fileManager

        Gluon.openRepo = { [weak self] url in
            XCTAssertEqual(url.path(), self?.repoPath)
            return .success(MockRepository.mock)
        }

        Gluon.printer = MockPrinter.mock
    }

    override func invokeTest() {
        let printer = Gluon.printer
        let openRepo = Gluon.openRepo
        let mockRepo = MockRepository.mock
        let fileManager = Gluon.fileManager
        let config = Configuration.configuration

        super.invokeTest()

        Configuration.configuration = config
        Gluon.fileManager = fileManager
        MockRepository.mock = mockRepo
        Gluon.openRepo = openRepo
        Gluon.printer = printer
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
