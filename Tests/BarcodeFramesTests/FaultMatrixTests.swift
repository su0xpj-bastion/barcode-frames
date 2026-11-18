import XCTest
import BarcodeFrames

/// Each planted bug must break exactly its pinned checks. About 2 s per fault.
final class FaultMatrixTests: XCTestCase {
    override func tearDown() { FaultInjection.active = [] }

    func testEveryFaultIsCaughtByItsPinnedChecks() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bf-faults")
        for fault in Fault.allCases {
            FaultInjection.active = [fault]
            let run = try Run.make(in: dir)
            let got = Set(allChecks.filter { !$0.run(run).isEmpty }.map { $0.name })
            XCTAssertFalse(got.isEmpty, "\(fault) slipped through every check")
            XCTAssertEqual(got, expectedFailures[fault] ?? [], "\(fault)")
        }
    }
}
