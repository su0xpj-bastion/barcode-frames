# Bugs and findings while building barcode-frames

Severity: S1 (data loss or privacy), S2 (wrong output), S3 (broken interaction), S4 (cosmetic).
All measured on Apple silicon, macOS 26.6. The commands are in the README.

### BF-1 · A 29.97 clip written with the default track timescale shows the wrong frame
**S2 / P0** · found by `fixture.exact` and `preview.frames`

- **Expected.** Output frame 170 (inside the 50% segment) shows source frame 325.
- **Actual.** It shows source frame 324.
- **Isolation.** Frame times in the written file were `20/600`, not `1001/30000`. AVAssetWriter's default `.mov` track timescale is 600, which can't represent 29.97 exactly, so every frame time was rounded.
- **Fix.** Set `mediaTimeScale = 30000` on the writer input.
- **Guard.** The fault `defaultTrackTimescale` re-plants it, and 3 checks must fail.

### BF-2 · Speed-changed segments export at a variable frame rate
**S2 / P1** · found by `export.constant-rate`

- **Actual.** Inside `scaleTimeRange` segments, both the composition reader and `AVAssetExportSession` (HighestQuality) write one frame per *source* frame, even with `frameDuration = 1001/30000`. `bf probe` counts gaps of 0.5 frame ×60, 1.0 ×279 and 2.0 ×30.
- **Fix.** `ConformingExporter` holds the newest frame at each output frame's leading edge, and writes a constant 29.97 file.

### BF-3 · The time-pitch algorithm moves audio that was never retimed
**S2 / P1** · found by `preview.sync`

- **Actual.** With retimed segments in the composition, clicks in plain segments land +1/+2 samples late with `.spectral`, 0 with `.timeDomain` (but 6.6 ms too long overall), and −46 with `.varispeed`.
- **Fix.** Pin `.spectral` and allow 2 samples, with the reason written down.

### BF-4 · Two bugs cancel out, so end-of-timeline sync passes with audio not retimed
**Test gap** · found by the fault matrix (`retimeVideoOnly` initially caught by nothing)

- **Isolation.** Unscaled 2× audio (60 frames in a 30-frame slot) and 50% audio (30 in 60) add up to the right total length.
- **Fix.** The structural check `edit.audio-follows-video` compares audio and video segment mappings directly.
