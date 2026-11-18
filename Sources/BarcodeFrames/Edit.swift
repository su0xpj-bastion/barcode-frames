import AVFoundation

public struct Segment: Equatable {
    public let sourceIn: Int
    /// Exclusive.
    public let sourceOut: Int
    /// speedNum / speedDen: 2/1 is twice as fast, 1/2 is half speed.
    public let speedNum: Int
    public let speedDen: Int

    public init(_ sourceIn: Int, _ sourceOut: Int, speed: (Int, Int) = (1, 1)) {
        self.sourceIn = sourceIn; self.sourceOut = sourceOut
        speedNum = speed.0; speedDen = speed.1
    }

    public var isRetimed: Bool { speedNum != speedDen }

    /// Output frames: round(source frames / speed).
    public var outputLength: Int {
        let n = (sourceOut - sourceIn) * speedDen, d = speedNum
        return (2 * n + d) / (2 * d)
    }
}

/// A single-track edit and what every output frame and click must be.
public struct EditPlan {
    public let segments: [Segment]

    public init(_ segments: [Segment]) { self.segments = segments }

    /// Two plain cuts around a 2x and a 50% retime.
    public static let sample = EditPlan([
        Segment(30, 120), Segment(200, 260, speed: (2, 1)), Segment(300, 330, speed: (1, 2)), Segment(400, 590),
    ])

    public var outputFrames: Int { segments.reduce(0) { $0 + $1.outputLength } }

    public func outputStart(_ i: Int) -> Int { segments[..<i].reduce(0) { $0 + $1.outputLength } }

    /// Source frame number each output frame must show.
    public func expectedSourceFrames() -> [Int] {
        segments.flatMap { s in (0..<s.outputLength).map { s.sourceIn + $0 * s.speedNum / s.speedDen } }
    }

    /// Where each click must land in the output, per segment.
    /// A click at source frame f lands at output frame start + (f - in) / speed, converted to samples.
    public func expectedClicks() -> [(window: Range<Int64>, samples: [Int64], retimed: Bool)] {
        segments.indices.map { i in
            let s = segments[i]
            let start = outputStart(i)
            let window = Clock.sample(frame: start)..<Clock.sample(frame: start + s.outputLength)
            let samples = Fixture.clickFrames(s.sourceOut).filter { $0 >= s.sourceIn }.map { f -> Int64 in
                // samples*10 = start*16016 + (srcSample(f)*10 - in*16016) * den / num, rounded
                let offset = (Clock.sample(frame: f) * 10 - Int64(s.sourceIn) * 16016) * Int64(s.speedDen) / Int64(s.speedNum)
                return (Int64(start) * 16016 + offset + 5) / 10
            }
            return (window, samples, s.isRetimed)
        }
    }
}

public struct BuiltEdit {
    public let composition: AVMutableComposition
    public let videoComposition: AVMutableVideoComposition
}

public enum EditError: Error { case noTrack(String) }

public enum EditBuilder {
    static func sourceTime(_ n: Int) -> CMTime {
        FaultInjection.on(.assumes30fps) ? CMTime(value: Int64(n), timescale: 30) : Clock.time(frames: n)
    }

    static func audioTime(_ t: CMTime) -> CMTime {
        FaultInjection.on(.audioMillisecondTimes) ? CMTime(seconds: t.seconds, preferredTimescale: 1000) : t
    }

    public static func build(_ plan: EditPlan, fixture: Fixture) throws -> BuiltEdit {
        let vAsset = AVURLAsset(url: fixture.videoURL), aAsset = AVURLAsset(url: fixture.audioURL)
        guard let srcV = vAsset.tracks(withMediaType: .video).first else { throw EditError.noTrack("video") }
        guard let srcA = aAsset.tracks(withMediaType: .audio).first else { throw EditError.noTrack("audio") }
        let comp = AVMutableComposition()
        let v = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        let a = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
        v.naturalTimeScale = 30000
        var cursor = CMTime.zero
        for s in plan.segments {
            let extra = FaultInjection.on(.cutIncludesOutFrame) ? 1 : 0
            let range = CMTimeRange(start: sourceTime(s.sourceIn), duration: sourceTime(s.sourceOut - s.sourceIn + extra))
            try v.insertTimeRange(range, of: srcV, at: cursor)
            try a.insertTimeRange(CMTimeRange(start: audioTime(range.start), duration: audioTime(range.duration)),
                                  of: srcA, at: audioTime(cursor))
            let out = Clock.time(frames: s.outputLength)
            if s.isRetimed {
                let inserted = CMTimeRange(start: cursor, duration: range.duration)
                v.scaleTimeRange(inserted, toDuration: out)
                if !FaultInjection.on(.retimeVideoOnly) { a.scaleTimeRange(inserted, toDuration: out) }
                cursor = cursor + out
            } else {
                cursor = cursor + range.duration
            }
        }
        let vc = AVMutableVideoComposition(propertiesOf: comp)
        vc.frameDuration = Clock.frameDuration
        vc.renderSize = CGSize(width: FrameCode.width, height: FrameCode.height)
        return BuiltEdit(composition: comp, videoComposition: vc)
    }
}
