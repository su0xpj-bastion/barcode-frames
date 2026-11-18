import XCTest
import BarcodeFrames

/// One XCTest per check over a single end-to-end run (fixture -> edit -> preview -> export).
final class CheckTests: XCTestCase {
    static var run: Run?

    func shared() throws -> Run {
        if let r = CheckTests.run { return r }
        FaultInjection.active = []
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bf-xctest")
        let r = try Run.make(in: dir)
        CheckTests.run = r
        return r
    }

    func assertPasses(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let check = try XCTUnwrap(allChecks.first { $0.name == name }, "no check named \(name)")
        for failure in check.run(try shared()) { XCTFail(failure, file: file, line: line) }
    }

    func testEveryCheckHasATest() {
        XCTAssertEqual(allChecks.count, 11)
    }

    func test_code_roundtrip() throws { try assertPasses("code.roundtrip") }
    func test_code_rejects_misread() throws { try assertPasses("code.rejects-misread") }
    func test_fixture_exact() throws { try assertPasses("fixture.exact") }
    func test_edit_duration() throws { try assertPasses("edit.duration") }
    func test_edit_audio_follows_video() throws { try assertPasses("edit.audio-follows-video") }
    func test_preview_frames() throws { try assertPasses("preview.frames") }
    func test_preview_sync() throws { try assertPasses("preview.sync") }
    func test_export_frames() throws { try assertPasses("export.frames") }
    func test_export_constant_rate() throws { try assertPasses("export.constant-rate") }
    func test_export_sync() throws { try assertPasses("export.sync") }
    func test_export_matches_preview() throws { try assertPasses("export.matches-preview") }
}
