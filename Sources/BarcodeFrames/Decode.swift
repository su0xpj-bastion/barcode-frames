import AVFoundation

public struct DecodedFrame: Equatable {
    public let pts: CMTime
    /// nil when the barcode failed its CRC.
    public let id: Int?
}

public struct Decoded {
    public let frames: [DecodedFrame]
    public let audio: [Float]
}

public enum DecodeError: Error { case reader(String), export(String) }

/// Reads what a viewer would actually see and hear: every rendered frame and every audio sample.
public enum Decoder {
    /// Pinned: the algorithm changes where un-retimed audio lands (see README).
    public static let pitch = AVAudioTimePitchAlgorithm.spectral

    static let bgra: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    static let pcm: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: Clock.sampleRate, AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
        AVLinearPCMIsBigEndianKey: false,
    ]

    /// The edit as the player renders it (no file written).
    public static func preview(_ edit: BuiltEdit) throws -> Decoded {
        let comp = edit.composition
        let vOut = AVAssetReaderVideoCompositionOutput(videoTracks: comp.tracks(withMediaType: .video), videoSettings: bgra)
        vOut.videoComposition = edit.videoComposition
        let aOut = AVAssetReaderAudioMixOutput(audioTracks: comp.tracks(withMediaType: .audio), audioSettings: pcm)
        aOut.audioTimePitchAlgorithm = Decoder.pitch
        return Decoded(frames: try frames(comp, vOut), audio: try samples(comp, aOut))
    }

    /// A rendered movie file.
    public static func file(_ url: URL) throws -> Decoded {
        let asset = AVURLAsset(url: url)
        guard let v = asset.tracks(withMediaType: .video).first, let a = asset.tracks(withMediaType: .audio).first
        else { throw DecodeError.reader("missing track in \(url.lastPathComponent)") }
        return Decoded(frames: try frames(asset, AVAssetReaderTrackOutput(track: v, outputSettings: bgra)),
                       audio: try samples(asset, AVAssetReaderTrackOutput(track: a, outputSettings: pcm)))
    }

    /// Source fixture video only.
    public static func sourceFrames(_ url: URL) throws -> [DecodedFrame] {
        let asset = AVURLAsset(url: url)
        guard let v = asset.tracks(withMediaType: .video).first else { throw DecodeError.reader("no video") }
        return try frames(asset, AVAssetReaderTrackOutput(track: v, outputSettings: bgra))
    }

    static func frames(_ asset: AVAsset, _ out: AVAssetReaderOutput) throws -> [DecodedFrame] {
        let reader = try AVAssetReader(asset: asset)
        out.alwaysCopiesSampleData = false
        reader.add(out)
        guard reader.startReading() else { throw DecodeError.reader("\(String(describing: reader.error))") }
        var result: [DecodedFrame] = []
        while let sb = out.copyNextSampleBuffer() {
            guard let pb = CMSampleBufferGetImageBuffer(sb) else { continue }
            CVPixelBufferLockBaseAddress(pb, .readOnly)
            let id = FrameCode.read(from: CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self),
                                    bytesPerRow: CVPixelBufferGetBytesPerRow(pb))
            CVPixelBufferUnlockBaseAddress(pb, .readOnly)
            result.append(DecodedFrame(pts: CMSampleBufferGetPresentationTimeStamp(sb), id: id))
        }
        guard reader.status == .completed else { throw DecodeError.reader("\(String(describing: reader.error))") }
        return result
    }

    static func samples(_ asset: AVAsset, _ out: AVAssetReaderOutput) throws -> [Float] {
        let reader = try AVAssetReader(asset: asset)
        reader.add(out)
        guard reader.startReading() else { throw DecodeError.reader("\(String(describing: reader.error))") }
        var result: [Float] = []
        while let sb = out.copyNextSampleBuffer() {
            guard let bb = CMSampleBufferGetDataBuffer(sb) else { continue }
            let n = CMBlockBufferGetDataLength(bb) / MemoryLayout<Float>.size
            var chunk = [Float](repeating: 0, count: n)
            chunk.withUnsafeMutableBytes { _ = CMBlockBufferCopyDataBytes(bb, atOffset: 0, dataLength: n * 4, destination: $0.baseAddress!) }
            result += chunk
        }
        return result
    }

    /// AVAssetExportSession with the HighestQuality preset. Kept for the `bf probe` comparison:
    /// inside retimed segments it writes one frame per source frame (variable frame rate).
    public static func stockExport(_ edit: BuiltEdit, to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        guard let s = AVAssetExportSession(asset: edit.composition, presetName: AVAssetExportPresetHighestQuality)
        else { throw DecodeError.export("no session") }
        s.outputURL = url
        s.outputFileType = .mov
        s.videoComposition = edit.videoComposition
        s.audioTimePitchAlgorithm = pitch
        let done = DispatchSemaphore(value: 0)
        s.exportAsynchronously { done.signal() }
        done.wait()
        guard s.status == .completed else { throw DecodeError.export("\(String(describing: s.error))") }
    }

    /// Sample index where each click starts: |x| > 0.2 after at least 1,000 quiet samples.
    public static func onsets(_ audio: [Float]) -> [Int64] {
        var result: [Int64] = [], quiet = 1000
        for (i, x) in audio.enumerated() {
            if abs(x) > 0.2 {
                if quiet >= 1000 { result.append(Int64(i)) }
                quiet = 0
            } else {
                quiet += 1
            }
        }
        return result
    }
}
