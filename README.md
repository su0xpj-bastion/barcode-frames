# barcode-frames

<!-- plain-english:begin -->
[![ci](https://github.com/su0xpj-bastion/barcode-frames/actions/workflows/ci.yml/badge.svg)](https://github.com/su0xpj-bastion/barcode-frames/actions/workflows/ci.yml)

End-to-end tests for video editing on Apple platforms where every frame wears a
name tag. The test clip has each frame's number drawn as a barcode, and the audio has a click
every 10 frames. It goes through a real edit (cuts, 2x speed, half speed) and a real export.
Then every frame and every audio sample is read back.

A dropped or doubled frame, or sound slipping off the picture, is invisible
in a quick look and obvious to a customer. Picture a stutter in a slow-motion wedding moment.
This catches it automatically, on every change.

- Swift and AVFoundation: generate the clip, build the edit, decode what the player shows and what the exported file contains, and check every frame and every click (to within 2 audio samples).
- An exporter that keeps a constant frame rate, because the standard export goes variable-rate inside speed changes.
- A SwiftUI inspector that shows the frame strip, and 6 planted bugs, each proven caught.

Along the way, the tests turned up:
- The default track clock (600 ticks per second) can't hold 29.97 exactly.
- The stock export writes variable frame rate inside retimes.
- The audio time-pitch algorithm shifts un-retimed audio by 1–2 samples.

Swift, AVFoundation (composition, reader/writer, export), XCTest, SwiftUI,
CI on GitHub Actions. Follows on from frame-exact, which checks the maths; this repo checks real
pixels and samples.

[Test plan](TEST_PLAN.md) · [Bugs found](BUGS.md) · [Test strategy](https://github.com/su0xpj-bastion/proof-sheet/blob/main/docs/TEST_STRATEGY.md)

---

## Technical detail
<!-- plain-english:end -->

End-to-end, frame-accurate tests for video editing on Apple platforms, in **Swift + AVFoundation + XCTest**, with a **SwiftUI** inspector.

Every frame of the test clip carries its own frame number as a block barcode (24 bits + CRC-8), and the audio has a click on the first sample of every 10th frame. The clip goes through a real edit: two cuts, a 2x retime and a 50% retime in an `AVMutableComposition`. The tests then decode **what the player renders** and **what the exported file contains**, and read the barcodes back. Each output frame must show exactly the source frame the edit promised, and each click must land within 2 samples (0.04 ms) of its picture.

It follows on from [frame-exact](https://github.com/su0xpj-bastion/frame-exact), which checks the timecode and edit math. This repo checks real pixels and samples.

```bash
swift test              # XCTest: one test per check, the fault matrix, unit tests (needs Xcode)
swift run bf            # the 11 checks on one end-to-end run, a few seconds
swift run bf faults     # plant each bug, confirm exactly its checks fail
swift run bf probe      # what AVAssetExportSession does with the same edit
scripts/build-local.sh check   # same CLI with plain swiftc, for machines with only Command Line Tools
```

## The pipeline

```
FixtureWriter      600 frames, ProRes 422, 640x360 at 29.97 (1001/30000), plus a 48 kHz WAV with clicks
EditBuilder        AVMutableComposition: 30-120 | 200-260 at 2x | 300-330 at 50% | 400-590  -> 370 frames
Decoder.preview    AVAssetReaderVideoCompositionOutput + AudioMixOutput: what playback renders
ConformingExporter AVAssetReader -> AVAssetWriter, H.264 + AAC, one frame every 1001/30000 s
Decoder.file       reads the export back; FrameCode.read turns pixels into frame numbers
```

## Checks

| Check | Fails when |
|---|---|
| `code.roundtrip`, `code.rejects-misread` | a frame number doesn't survive encode/decode, or a single flipped block is accepted |
| `fixture.exact` | the source clip has a wrong frame or a frame time that isn't `n * 1001/30000` |
| `edit.duration` | the composition isn't exactly 370 frames |
| `edit.audio-follows-video` | an audio segment's target or source range differs from its video segment |
| `preview.frames`, `export.frames` | any output frame shows the wrong source frame, or can't be read |
| `preview.sync`, `export.sync` | a click in an un-retimed segment is more than 2 samples off its picture |
| `export.constant-rate` | an exported frame isn't at exactly `k * 1001/30000` |
| `export.matches-preview` | the file shows something different from playback |

## Fault matrix

`bf faults` and `FaultMatrixTests` turn each bug on by itself and require the exact pinned set of failing checks:

| Planted bug | Caught by | What the check reports |
|---|---|---|
| `defaultTrackTimescale` | fixture, preview, export frames | `source frame 1 at 20/600, want 1001/30000` |
| `assumes30fps` | duration, frames, sync (5) | `composition is 370090/30000, want 370370/30000` |
| `cutIncludesOutFrame` | duration, frames, sync (5) | `output frame 90 shows 120, want source 200` |
| `retimeVideoOnly` | audio-follows-video | `4 video segments but 5 audio segments` |
| `audioMillisecondTimes` | audio-follows-video, both syncs | `segment 1 audio is 49 samples (1.02 ms) off picture` |
| `conformSamplesFrameCenter` | preview and export frames | `output frame 91 shows 203, want source 202` |

## Findings

All measured on a MacBook (Apple Silicon, macOS 26.6), and reproducible with the commands above.

1. **AVAssetWriter's default `.mov` track timescale is 600**, which cannot represent 1001/30000. A 29.97 source written without `mediaTimeScale = 30000` gets frame times of `20/600` instead of `1001/30000`, and inside the 50% segment output frame 170 showed source frame 324 instead of 325. The fixture now sets the timescale, and `defaultTrackTimescale` plants the bug again.
2. **Retimed segments come out at a variable frame rate.** Inside a `scaleTimeRange` segment, both the composition reader and `AVAssetExportSession` (HighestQuality) emit one frame per *source* frame, even with `frameDuration = 1001/30000`. `bf probe` on the 370-frame timeline counts gaps of 0.5 frame x60, 1.0 x279 and 2.0 x30. `ConformingExporter` holds the newest frame at each output frame's leading edge and writes a constant 29.97 file (`export.constant-rate`).
3. **The time-pitch algorithm moves audio that was never retimed.** Read through `AVAssetReaderAudioMixOutput`, with retimed segments in the composition, clicks in the plain segments land at:

   | `audioTimePitchAlgorithm` | offset in plain segments | total length vs 592,592 samples |
   |---|---|---|
   | `.spectral` (pinned) | +1 / +2 samples | +2 |
   | `.timeDomain` | 0 | +317 (6.6 ms long) |
   | `.varispeed` | −46 samples (~1 ms early) | +1 |

   A composition with one plain segment and the default algorithm puts every click on its exact sample. The pipeline pins `.spectral` and allows 2 samples.
4. **Bugs can cancel out.** With this edit, `retimeVideoOnly` left the final segment perfectly in sync: the unscaled 2x audio (60 frames in a 30-frame slot) and 50% audio (30 in 60) add up to the right length. End-of-timeline sync passed, so the bug is caught by comparing audio and video segment mappings instead.
5. **Clicks don't survive time-stretching well enough to time them.** In the spectral-retimed segments only 5 of 6 and 2 of 3 clicks were detectable, so sync timing is checked in plain segments only, and retimed audio is checked structurally (finding 4).

## SwiftUI inspector

`BarcodeFramesUI.FrameStripView` draws the timeline as one tile per output frame, coloured by segment, with mismatches tall and red; tap one to see expected vs actual. Its `FrameStripModel` is pure, so XCTest covers it without a window.

## Where this stops

- One video track and one mono audio track; constant-speed retimes only; no transitions or effects.
- 640x360 synthetic content. The barcode survives H.264 at 6 Mb/s; it is not a test of image quality.
- No XCUITest: SwiftPM can't host a UI test target. The SwiftUI view is a library, tested through its model.
- Written on a Mac with only Command Line Tools: checks and faults run locally through `scripts/build-local.sh`; `swift test` runs on GitHub Actions macOS runners.
