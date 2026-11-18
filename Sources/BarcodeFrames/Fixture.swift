import AVFoundation

/// 29.97 fps timing shared by the fixture, the edit, and the checks.
public enum Clock {
    public static let frameDuration = CMTime(value: 1001, timescale: 30000)
    public static let sampleRate = 48_000

    public static func time(frames n: Int) -> CMTime { CMTime(value: Int64(n) * 1001, timescale: 30000) }

    /// First audio sample of a frame: round(n * 1601.6).
    public static func sample(frame n: Int) -> Int64 { (Int64(n) * 16016 + 5) / 10 }
}

public struct Fixture {
    public let videoURL: URL
    public let audioURL: URL
    public let frames: Int

    public init(videoURL: URL, audioURL: URL, frames: Int) {
        self.videoURL = videoURL; self.audioURL = audioURL; self.frames = frames
    }
    /// Source frames that carry an audio click at their first sample.
    public static func clickFrames(_ frames: Int) -> [Int] { stride(from: 5, to: frames, by: 10).map { $0 } }
}

public enum FixtureError: Error { case writer(String) }

/// Writes a ProRes 422 clip whose every frame carries its own number, plus a 48 kHz WAV
/// with a 3 kHz click at the first sample of every 10th frame (5, 15, 25, ...).
public enum FixtureWriter {
    public static func write(frames: Int, to dir: URL) throws -> Fixture {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let video = dir.appendingPathComponent("source.mov"), audio = dir.appendingPathComponent("source.wav")
        try? FileManager.default.removeItem(at: video)
        try? FileManager.default.removeItem(at: audio)
        try writeVideo(frames: frames, url: video)
        try writeAudio(frames: frames, url: audio)
        return Fixture(videoURL: video, audioURL: audio, frames: frames)
    }

    static func writeVideo(frames: Int, url: URL) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.proRes422,
            AVVideoWidthKey: FrameCode.width, AVVideoHeightKey: FrameCode.height,
        ])
        input.expectsMediaDataInRealTime = false
        // Default .mov track timescale is 600, which cannot hold 1001/30000: every frame time is rounded.
        if !FaultInjection.on(.defaultTrackTimescale) { input.mediaTimeScale = 30000 }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: FrameCode.width, kCVPixelBufferHeightKey as String: FrameCode.height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw FixtureError.writer("\(String(describing: writer.error))") }
        writer.startSession(atSourceTime: .zero)
        for i in 0..<frames {
            while !input.isReadyForMoreMediaData { usleep(500) }
            var buf: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buf)
            guard let pb = buf else { throw FixtureError.writer("no pixel buffer") }
            CVPixelBufferLockBaseAddress(pb, [])
            FrameCode.draw(id: i, into: CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self),
                           bytesPerRow: CVPixelBufferGetBytesPerRow(pb))
            CVPixelBufferUnlockBaseAddress(pb, [])
            guard adaptor.append(pb, withPresentationTime: Clock.time(frames: i)) else {
                throw FixtureError.writer("append \(i): \(String(describing: writer.error))")
            }
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw FixtureError.writer("\(String(describing: writer.error))") }
    }

    static func writeAudio(frames: Int, url: URL) throws {
        let total = Int(Clock.sample(frame: frames))
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(Clock.sampleRate), channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total))!
        buffer.frameLength = AVAudioFrameCount(total)
        let ch = buffer.floatChannelData![0]
        for i in 0..<total { ch[i] = 0 }
        for f in Fixture.clickFrames(frames) {
            let s = Int(Clock.sample(frame: f))
            for k in 0..<96 where s + k < total {
                ch[s + k] = 0.8 * Float(sin(2 * Double.pi * 3000 * Double(k) / Double(Clock.sampleRate) + Double.pi / 2))
            }
        }
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: Clock.sampleRate, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    }
}
