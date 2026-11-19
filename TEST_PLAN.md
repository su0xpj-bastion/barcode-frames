# Test plan: barcode-frames

Follows the shared [test strategy](https://github.com/su0xpj-bastion/proof-sheet/blob/main/docs/TEST_STRATEGY.md). Real bugs from building it are in [BUGS.md](BUGS.md).

**In scope:** a real AVFoundation edit (two cuts, 2x and 50% retimes) from source through preview and export, checked frame by frame and sample by sample.

**Out of scope:** speed ramps, effects and transitions; HDR video; real footage.

## What must be true, and how it's checked

| Requirement | Priority | How it is checked |
|---|---|---|
| Every output frame shows the source frame the edit promised | P0 | barcode on every frame, read from preview and from the exported file |
| Sound stays on picture | P0 | clicks within 2 samples in plain segments; audio and video segment mappings match |
| Export is constant frame rate | P1 | frame-gap census of the exported file |
| The fixture itself is exact | P0 | every source frame and click verified before any edit is tested |

## How it runs

- **Every push (CI):** all checks, then the fault matrix (each planted bug switched on alone must fail exactly its pinned checks).
- **Locally:** the same checks through the command-line tool (`scripts/build-local.sh`), on a Mac with only the Command Line Tools.

## Exit criteria

11 checks pass; the fault matrix is exact (6/6); the SwiftUI inspector model passes its unit tests. CI is green on the default branch.

## Risks

- Test media is generated, so every answer is exact. Real-world media needs licensed sets run through the same checks.
- Simulators and CI machines are not real devices. Timing and hardware behaviour need a real-device pass before release.
