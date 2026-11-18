import Foundation

/// Editing and export bugs that can be switched on to prove the checks catch them.
public enum Fault: String, CaseIterable {
    /// Source written with the default .mov track timescale (600), which cannot hold 1001/30000.
    case defaultTrackTimescale
    /// Source times computed at 30 fps for 29.97 media.
    case assumes30fps
    /// Cut includes its out-point frame (inclusive range).
    case cutIncludesOutFrame
    /// Retime applied to the video track only.
    case retimeVideoOnly
    /// Audio edit times rounded to whole milliseconds.
    case audioMillisecondTimes
    /// Conform samples the middle of each output frame instead of its leading edge.
    case conformSamplesFrameCenter
}

public enum FaultInjection {
    public static var active: Set<Fault> = {
        let raw = ProcessInfo.processInfo.environment["BF_FAULTS"] ?? ""
        return Set(raw.split(separator: ",").compactMap { Fault(rawValue: String($0)) })
    }()

    static func on(_ f: Fault) -> Bool { active.contains(f) }
}
