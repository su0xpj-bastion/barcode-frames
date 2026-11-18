import XCTest
import CoreMedia
@testable import BarcodeFrames
import BarcodeFramesUI

final class UnitTests: XCTestCase {
    func testPlanExpectations() {
        let plan = EditPlan.sample
        XCTAssertEqual(plan.outputFrames, 370)
        let want = plan.expectedSourceFrames()
        XCTAssertEqual(Array(want[89...92]), [119, 200, 202, 204])   // cut into the 2x segment
        XCTAssertEqual(Array(want[120...123]), [300, 300, 301, 301]) // 50%: each frame twice
    }

    func testRetimedLengthRounds() {
        XCTAssertEqual(Segment(0, 101, speed: (2, 1)).outputLength, 51)
        XCTAssertEqual(Segment(0, 30, speed: (1, 2)).outputLength, 60)
    }

    func testConformHoldsLeadingEdgeFrame() {
        // A renderer stream at 2x: frames every half frame, nanosecond timestamps rounded up.
        let pts = (0..<8).map { CMTime(value: Int64(($0 * 1001 * 1_000_000_000 / 60000) + 1), timescale: 1_000_000_000) }
        XCTAssertEqual(Conform.pick(pts, count: 4), [0, 2, 4, 6])
    }

    func testOnsetsNeedQuietBeforeThem() {
        var a = [Float](repeating: 0, count: 5000)
        a[1200] = 0.5; a[1300] = 0.5; a[3000] = -0.5
        XCTAssertEqual(Decoder.onsets(a), [1200, 3000])
    }

    func testStripModelFlagsMismatches() {
        let plan = EditPlan([Segment(0, 3)])
        let decoded = [0, 1, 5].enumerated().map { DecodedFrame(pts: Clock.time(frames: $0.offset), id: $0.element) }
        let m = FrameStripModel(plan: plan, decoded: decoded)
        XCTAssertEqual(m.mismatches.map { $0.id }, [2])
        XCTAssertEqual(m.summary, "1 of 3 frames wrong, first at output frame 2")
    }
}
