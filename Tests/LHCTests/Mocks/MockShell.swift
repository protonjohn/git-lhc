//
//
//  Created by John Biggs on 15.01.24.
//

import Foundation

@testable import LHC
@testable import LHCInternal

struct MockShell: Shellish {
    var printedItems: [(String, error: Bool)] = []

    func run(shebang: String, command: String, environment: [String : String], ttyEnvironmentVariable: String?, extraFileDescriptors: [Int32 : FileHandle]) throws -> AsyncStream<Result<LHCInternal.Shell.Event, Error>> {
        return AsyncStream {
            $0.finish()
        }
    }

    mutating func print(_ item: String, error: Bool) {
        printedItems.append((item, error))
    }

    static var mock = Self()
}
