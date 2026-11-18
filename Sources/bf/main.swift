import BarcodeFrames
import AVFoundation

let args = Array(CommandLine.arguments.dropFirst())
let work = URL(fileURLWithPath: ProcessInfo.processInfo.environment["BF_WORK"] ?? NSTemporaryDirectory())
    .appendingPathComponent("barcode-frames")

func failing(_ run: Run) -> [String: [String]] {
    var res: [String: [String]] = [:]
    for c in allChecks { res[c.name] = c.run(run) }
    return res
}

do {
    switch args.first ?? "check" {
    case "check":
        let res = failing(try Run.make(in: work))
        var failed = 0
        for c in allChecks {
            let f = res[c.name]!
            print("\(f.isEmpty ? "PASS" : "FAIL")  \(c.name)")
            for m in f.prefix(3) { print("      \(m)") }
            if !f.isEmpty { failed += 1 }
        }
        print("\n\(allChecks.count - failed)/\(allChecks.count) checks passed  (movies in \(work.path))")
        exit(failed == 0 ? 0 : 1)
    case "faults":
        var bad = 0
        for fault in [nil] + Fault.allCases.map({ Optional($0) }) {
            FaultInjection.active = fault.map { [$0] } ?? []
            let got = Set(failing(try Run.make(in: work)).filter { !$0.value.isEmpty }.keys)
            let want = fault.flatMap { expectedFailures[$0] } ?? []
            let ok = got == want && (fault == nil || !got.isEmpty)
            if !ok { bad += 1 }
            let label = fault?.rawValue ?? "clean run"
            print("\(ok ? (fault == nil ? "PASS  " : "CAUGHT") : "MISMATCH")  \(label): \(got.isEmpty ? "-" : got.sorted().joined(separator: ", "))")
            if !ok { print("          expected: \(want.sorted().joined(separator: ", "))") }
        }
        FaultInjection.active = []
        print("\n\(Fault.allCases.count + 1 - bad)/\(Fault.allCases.count + 1) fault-matrix rows as pinned")
        exit(bad == 0 ? 0 : 1)
    case "probe":
        // Platform behavior, reported rather than gated: what the stock export path does.
        let fx = try FixtureWriter.write(frames: 600, to: work)
        let plan = EditPlan.sample
        let edit = try EditBuilder.build(plan, fixture: fx)
        let stock = work.appendingPathComponent("stock-export.mov")
        try Decoder.stockExport(edit, to: stock)
        let frames = try Decoder.file(stock).frames
        var steps: [String: Int] = [:]
        for (a, b) in zip(frames, frames.dropFirst()) { steps[String(format: "%.1f", (b.pts - a.pts).seconds * 30000 / 1001), default: 0] += 1 }
        print("AVAssetExportSession (HighestQuality): \(frames.count) frames for a \(plan.outputFrames)-frame timeline")
        print("  gaps between frames, in 29.97 frames: \(steps.sorted { $0.key < $1.key }.map { "\($0.key) x\($0.value)" }.joined(separator: ", "))")
        let mismatch = zip(Conform.frames(frames, count: plan.outputFrames), plan.expectedSourceFrames()).filter { $0.0.id != $0.1 }.count
        print("  after conforming to 29.97: \(mismatch) wrong frames")
    default:
        print("usage: bf [check | faults | probe]   (BF_WORK sets the scratch folder)"); exit(2)
    }
} catch {
    print("error: \(error)"); exit(1)
}
