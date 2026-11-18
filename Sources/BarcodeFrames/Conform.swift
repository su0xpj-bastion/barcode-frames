import AVFoundation

/// Turns the renderer's frame stream into one frame per timeline frame.
///
/// Inside a retimed segment the renderer emits one frame per *source* frame: every half frame
/// at 2x, every second frame at 50%. A 29.97 timeline needs exactly one frame every 1001/30000 s,
/// so each output frame k shows the newest rendered frame at its leading edge, k * 1001/30000.
public enum Conform {
    /// Small allowance for renderer timestamps in nanoseconds (3036366667 ns for 91 frames).
    static let slack = CMTime(value: 1, timescale: 1000)

    static func edge(_ k: Int) -> CMTime {
        let t = Clock.time(frames: k)
        return FaultInjection.on(.conformSamplesFrameCenter) ? t + CMTime(value: 1001, timescale: 60000) : t + slack
    }

    /// Index into `pts` shown at each of `count` output frames (nil before the first frame).
    public static func pick(_ pts: [CMTime], count: Int) -> [Int?] {
        var result: [Int?] = [], i = -1
        for k in 0..<count {
            while i + 1 < pts.count && pts[i + 1] <= edge(k) { i += 1 }
            result.append(i >= 0 ? i : nil)
        }
        return result
    }

    public static func frames(_ decoded: [DecodedFrame], count: Int) -> [DecodedFrame] {
        pick(decoded.map { $0.pts }, count: count).enumerated().map { k, i in
            DecodedFrame(pts: Clock.time(frames: k), id: i.flatMap { decoded[$0].id })
        }
    }
}

/// Renders the edit to a constant-frame-rate H.264 + AAC movie: every frame at k * 1001/30000.
public enum ConformingExporter {
    public static func export(_ edit: BuiltEdit, frames count: Int, to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let comp = edit.composition
        let vReader = try AVAssetReader(asset: comp), aReader = try AVAssetReader(asset: comp)
        let vOut = AVAssetReaderVideoCompositionOutput(videoTracks: comp.tracks(withMediaType: .video), videoSettings: Decoder.bgra)
        vOut.videoComposition = edit.videoComposition
        let aOut = AVAssetReaderAudioMixOutput(audioTracks: comp.tracks(withMediaType: .audio), audioSettings: Decoder.pcm)
        aOut.audioTimePitchAlgorithm = Decoder.pitch
        vReader.add(vOut); aReader.add(aOut)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: FrameCode.width, AVVideoHeightKey: FrameCode.height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000],
        ])
        vIn.mediaTimeScale = 30000
        vIn.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vIn, sourcePixelBufferAttributes: nil)
        let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: Clock.sampleRate, AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 192_000,
        ])
        aIn.expectsMediaDataInRealTime = false
        writer.add(vIn); writer.add(aIn)
        guard vReader.startReading(), aReader.startReading(), writer.startWriting()
        else { throw DecodeError.export("start: \(String(describing: writer.error ?? vReader.error ?? aReader.error))") }
        writer.startSession(atSourceTime: .zero)

        let group = DispatchGroup()
        var failure: String?
        // Video: hold the newest rendered frame at each output frame's leading edge.
        group.enter()
        var k = 0
        var current: CMSampleBuffer?, next = vOut.copyNextSampleBuffer()
        vIn.requestMediaDataWhenReady(on: DispatchQueue(label: "video")) {
            while vIn.isReadyForMoreMediaData {
                if k == count { vIn.markAsFinished(); group.leave(); return }
                while let n = next, CMSampleBufferGetPresentationTimeStamp(n) <= Conform.edge(k) {
                    current = n; next = vOut.copyNextSampleBuffer()
                }
                guard let c = current, let pb = CMSampleBufferGetImageBuffer(c),
                      adaptor.append(pb, withPresentationTime: Clock.time(frames: k))
                else { failure = "video frame \(k): \(String(describing: writer.error))"; vIn.markAsFinished(); group.leave(); return }
                k += 1
            }
        }
        // Audio: pass the mixed PCM through to the AAC encoder unchanged.
        group.enter()
        aIn.requestMediaDataWhenReady(on: DispatchQueue(label: "audio")) {
            while aIn.isReadyForMoreMediaData {
                guard let sb = aOut.copyNextSampleBuffer() else { aIn.markAsFinished(); group.leave(); return }
                if !aIn.append(sb) { failure = "audio: \(String(describing: writer.error))"; aIn.markAsFinished(); group.leave(); return }
            }
        }
        group.wait()
        vReader.cancelReading(); aReader.cancelReading()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        if let f = failure { throw DecodeError.export(f) }
        guard writer.status == .completed else { throw DecodeError.export("\(String(describing: writer.error))") }
    }
}
