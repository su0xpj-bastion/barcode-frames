import AVFoundation

/// Everything one end-to-end run produces: the fixture as decoded, the edit, what the
/// player renders, and what the conformed export file contains.
public struct Run {
    public let plan: EditPlan
    public let source: [DecodedFrame]
    public let compositionDuration: CMTime
    /// (target, source) time ranges of each composition segment, per media type.
    public let videoMapping: [CMTimeMapping]
    public let audioMapping: [CMTimeMapping]
    public let preview: Decoded
    public let export: Decoded

    /// Writes a fresh fixture, builds the edit, renders the preview, exports and decodes the file.
    public static func make(plan: EditPlan = .sample, in dir: URL) throws -> Run {
        let fx = try FixtureWriter.write(frames: 600, to: dir)
        let edit = try EditBuilder.build(plan, fixture: fx)
        let out = dir.appendingPathComponent("export.mov")
        try ConformingExporter.export(edit, frames: plan.outputFrames, to: out)
        return Run(plan: plan, source: try Decoder.sourceFrames(fx.videoURL),
                   compositionDuration: edit.composition.duration,
                   videoMapping: edit.composition.tracks(withMediaType: .video).first!.segments.map { $0.timeMapping },
                   audioMapping: edit.composition.tracks(withMediaType: .audio).first!.segments.map { $0.timeMapping },
                   preview: try Decoder.preview(edit), export: try Decoder.file(out))
    }
}

public struct Check {
    public let name: String
    public let run: (Run) -> [String]
}

/// Audio tolerance for un-retimed segments, in samples (2 = 0.04 ms). See README for why not 0.
public let syncToleranceSamples: Int64 = 2

func frameIDs(_ got: [DecodedFrame], _ want: [Int], _ label: String) -> [String] {
    var out: [String] = []
    if got.count != want.count { out.append("\(label): \(got.count) frames, want \(want.count)") }
    for (k, (g, w)) in zip(got, want).enumerated() where g.id != w {
        out.append("\(label): output frame \(k) shows \(g.id.map(String.init) ?? "unreadable"), want source \(w)")
        if out.count >= 4 { break }
    }
    return out
}

func sync(_ audio: [Float], _ plan: EditPlan, _ label: String) -> [String] {
    var out: [String] = []
    let onsets = Decoder.onsets(audio)
    for (i, c) in plan.expectedClicks().enumerated() where !c.retimed {
        let got = onsets.filter { c.window.contains($0) }
        if got.count != c.samples.count { out.append("\(label): segment \(i + 1) has \(got.count) clicks, want \(c.samples.count)"); continue }
        let worst = zip(got, c.samples).map { $0.0 - $0.1 }.max { abs($0) < abs($1) } ?? 0
        if abs(worst) > syncToleranceSamples {
            out.append("\(label): segment \(i + 1) audio is \(worst) samples (\(String(format: "%.2f", Double(worst) / 48)) ms) off picture")
        }
    }
    return out
}

public let allChecks: [Check] = [
    Check(name: "code.roundtrip") { _ in
        var out: [String] = []
        for id in [0, 1, 599, 0x5A5A5A, FrameCode.maxID] + (0..<500).map({ $0 * 33_331 % FrameCode.maxID }) {
            if FrameCode.decode(bits: FrameCode.bits(for: id)) != id { out.append("id \(id) does not round-trip") }
        }
        return out
    },
    Check(name: "code.rejects-misread") { _ in
        var out: [String] = []
        for id in [0, 7, 4242, FrameCode.maxID] {
            for b in 0..<32 {
                var bits = FrameCode.bits(for: id)
                bits[b].toggle()
                if FrameCode.decode(bits: bits) != nil { out.append("id \(id) with block \(b) flipped was accepted") }
            }
        }
        return out
    },
    Check(name: "fixture.exact") { r in
        var out = frameIDs(r.source, Array(0..<600), "source")
        for (i, f) in r.source.enumerated() where f.pts != Clock.time(frames: i) {
            out.append("source frame \(i) at \(f.pts.value)/\(f.pts.timescale), want \(Int64(i) * 1001)/30000"); break
        }
        return out
    },
    Check(name: "edit.duration") { r in
        let want = Clock.time(frames: r.plan.outputFrames)
        return r.compositionDuration == want ? [] :
            ["composition is \(r.compositionDuration.value)/\(r.compositionDuration.timescale), want \(want.value)/30000 (\(r.plan.outputFrames) frames)"]
    },
    Check(name: "edit.audio-follows-video") { r in
        func f(_ t: CMTime) -> String { String(format: "%.3f", t.seconds * 30000 / 1001) }
        func show(_ m: CMTimeMapping) -> String { "\(f(m.target.start))+\(f(m.target.duration)) <- \(f(m.source.start))+\(f(m.source.duration))" }
        guard r.videoMapping.count == r.audioMapping.count else {
            return ["\(r.videoMapping.count) video segments but \(r.audioMapping.count) audio segments: " +
                    r.audioMapping.map(show).joined(separator: ", ")]
        }
        for (i, (v, a)) in zip(r.videoMapping, r.audioMapping).enumerated()
        where v.target != a.target || v.source != a.source {
            return ["segment \(i + 1): video \(show(v)), audio \(show(a)) (in frames)"]
        }
        return []
    },
    Check(name: "preview.frames") { r in
        frameIDs(Conform.frames(r.preview.frames, count: r.plan.outputFrames), r.plan.expectedSourceFrames(), "preview")
    },
    Check(name: "preview.sync") { r in sync(r.preview.audio, r.plan, "preview") },
    Check(name: "export.frames") { r in frameIDs(r.export.frames, r.plan.expectedSourceFrames(), "export") },
    Check(name: "export.constant-rate") { r in
        for (k, f) in r.export.frames.enumerated() where f.pts != Clock.time(frames: k) {
            return ["export frame \(k) at \(f.pts.value)/\(f.pts.timescale), want \(Int64(k) * 1001)/30000"]
        }
        return []
    },
    Check(name: "export.sync") { r in sync(r.export.audio, r.plan, "export") },
    Check(name: "export.matches-preview") { r in
        let p = Conform.frames(r.preview.frames, count: r.plan.outputFrames).map { $0.id }
        let e = r.export.frames.map { $0.id }
        guard let k = zip(p, e).enumerated().first(where: { $0.element.0 != $0.element.1 })?.offset else {
            return p.count == e.count ? [] : ["preview has \(p.count) frames, export \(e.count)"]
        }
        return ["frame \(k): preview shows \(p[k] ?? -1), export shows \(e[k] ?? -1)"]
    },
]

/// Which checks each fault must break. Pinned: a change here is a review signal.
public let expectedFailures: [Fault: Set<String>] = [
    .defaultTrackTimescale: ["fixture.exact", "preview.frames", "export.frames"],
    .assumes30fps: ["edit.duration", "preview.frames", "preview.sync", "export.frames", "export.sync"],
    .cutIncludesOutFrame: ["edit.duration", "preview.frames", "preview.sync", "export.frames", "export.sync"],
    .retimeVideoOnly: ["edit.audio-follows-video"],
    .audioMillisecondTimes: ["edit.audio-follows-video", "preview.sync", "export.sync"],
    .conformSamplesFrameCenter: ["preview.frames", "export.frames"],
]
