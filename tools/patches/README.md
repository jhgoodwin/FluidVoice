# FluidAudio Nemotron compatibility patch

Base FluidAudio revision: `3fd63887eef1dc25edea8263ce4b44aa854d898b`.

`fluidaudio-nemotron-compatibility.patch` preserves the independent dependency work. The current
development workspace points the app at that maintained local checkout; this must become a
published immutable fork revision before merge. Apply the patch at the base revision with
`git apply --check` followed by `git apply`. Do not patch Xcode DerivedData.
The current working checkout is `.local-dependencies/FluidAudio`, branch `codex/nemotron-diarization`;
that workspace is ignored, and this patch includes all nine changed/new source and test files.

Implemented: configurable speaker count, explicit Nemotron tensor geometry, strict shape/dtype and
length validation, Float16 output decoding, caller-controlled compute configuration, local compiled
model loading, cancellation checks around loading, and overflow-checked dimension validation.
The Nemotron factory preserves the explicitly supplied update cadence, including 300, rather than
silently applying the older Sortformer clamp to 340. Cache scoring parameters remain explicit. The
host mel ABI is frozen per model family: Nemotron uses the checked-in NeMo settings and frame-count
semantics, while legacy Sortformer retains its existing framing behavior. Complete-file Nemotron
processing emits the final core tail instead of leaving it as right-context-only audio. Streaming
state rejects inconsistent buffers and invalid reported embedding lengths.

Verified: the 67-test Sortformer/legacy integration selection passed, and the 10-test Nemotron
compatibility suite passed with the actual local CoreML artifact. The real-model suite loads the
model and runs one complete fixed window plus its final core tail end-to-end. It is enabled with
`NEMOTRON_DIARIZATION_MODEL_PATH` pointing to an `.mlpackage` or `.mlmodelc` directory. No model weights
are included in the patch or the DMG.

This establishes the Swift runtime contract and end-to-end execution. Model quality and performance
measurements are intentionally out of scope because they were completed separately. Once the
dependency changes are committed to the maintained fork, update the app's Xcode and Swift package
pins together.

# FluidAudio Parakeet preprocessor compute-units patch (Nov 2026)

Base FluidAudio revision: `386f7195670b77f2954c7ee143ec63fcb50b6c3b` (altic-dev/FluidAudio `main`
at the time). `fluidaudio-preprocessor-compute-units.patch` applies cleanly there. It is published as
commit `3857a6d56aad6c1de4df47e072484d000ad3de9a` on jhgoodwin/FluidAudio, branch
`fix/preprocessor-compute-units`. `Package.swift`, `Fluid.xcodeproj/project.pbxproj`, and both
`Package.resolved` files pin that revision; only the FluidAudio entries differ from upstream.

## Symptom

Dictating with Parakeet (seen on Fluid Speech Pro), the live preview kept rewriting the sentence:
words appeared, vanished, and reappeared on successive preview ticks, worst when the user paused
or kept holding the hotkey after speaking. The final transcript often lost words from the middle or
end. Example (log session 33): preview alternated between
`...the fast end of the dictation, if it keeps rewriting the last part of my sentence or not.` and
`...the fast`; the final kept `...the fast if it keeps rewriting...`. AI cleanup was not involved:
it received the already-truncated text and returned it unchanged.

## Root cause (what we found)

Not silence, not AI cleanup, and not "Faster Long Dictation" (those were suspected first; the bug
reproduced with that setting off and with no trailing silence at all).

- The Parakeet `Preprocessor.mlmodelc` (mel spectrogram + per-feature mean/std normalization) is
  hard-coded to `.cpuOnly` in `AsrModels.createModelSpecs`. It ignores the caller's configuration.
- On this machine (macOS 15.6.1, Apple Silicon) the CPU result is wrong and nondeterministic.
  Identical input bytes produce different mel output across runs. In the bad runs, every frame past
  a cut point is computed as "no sound" (all 128 rows at their minimum); cuts seen at frame 411
  (~4.1 s) and 821 (~8.2 s). The encoder then sees silence and drops all words past the cut.
- Live preview re-runs the preprocessor every ~0.6 s, so each tick got a different cut point. That
  is the flicker. The final decode is one more draw, so it kept whichever cut it got.
- Measured with a standalone harness that runs only the preprocessor on identical input:
  - `.cpuOnly`: cut at frame 411 every run, including on a synthetic 15 s tone+noise clip with no
    silence and no speech.
  - `.cpuAndNeuralEngine`: same failure as CPU (probably still executes on CPU).
  - `.cpuAndGPU` and `.all`: clean on every run (30/30 per configuration).
  - Full pipeline on the user's recording: CPU correct about 1 in 4; preprocessor on GPU 18/18.
- Why it fails on CPU, and why frame 411, is not understood. Moving off CPU avoids it; it does not
  explain it.

## Why a setting and not a hard-coded fix

Upstream FluidInference/FluidAudio hit the opposite failure: issue #1074 / PR #1079 (Oct 2026)
moved a different mel model (CTC keyword spotter) *onto* CPU because the Neural Engine broke it on
macOS 27.0.1 (M1 Pro, M4 Max). Upstream `main` still pins the Parakeet preprocessor to `.cpuOnly`
and has no issue matching this bug. So the safe choice differs by OS/hardware. The patch makes it
selectable; the app exposes it as a setting; the default stays `.cpuOnly` (no behavior change for
existing users).

## What changed

FluidAudio (this patch, `Sources/FluidAudio/ASR/Parakeet/AsrModels.swift` only):
- `public static let defaultPreprocessorComputeUnits: MLComputeUnits = .cpuOnly`.
- Optional `preprocessorComputeUnits: MLComputeUnits? = nil` on `load`, `loadLocalOnly`,
  `downloadAndLoad`, threaded into `createModelSpecs`. `nil` keeps prior behavior. Fused
  preprocessor+encoder models (110M) ignore it, as before.

App:
- `SettingsStore.ParakeetPreprocessorComputeUnits` (CPU default / CPU + GPU / CPU + Neural Engine /
  All), key `ParakeetPreprocessorComputeUnits`. The doc comment there records the findings above.
- `FluidAudioProvider` passes it to both model-load calls and logs
  `Parakeet preprocessor compute units=<value>` at load.
- Settings → Experimental → "Speech Preprocessor Hardware" dropdown (under Faster Long Dictation),
  searchable. Changing it calls `resetTranscriptionProvider()` and then `ensureAsrReady`, matching
  `VoiceEngineSettingsViewModel.activateSpeechModel`. Reset alone leaves the model unloaded, and the
  next recording then has no live preview (this happened in the first manual test).
- `BackupService`: optional field, so older backups still decode.

## Verification done

- Manual, one Mac (macOS 15.6.1, Apple Silicon, Fluid Speech Pro), setting = CPU + GPU: the live
  preview grew monotonically over 25 ticks, never removed a word, held identical text through a
  pause, and the final (fresh full decode) matched the last preview at 171 chars. Previously, on CPU,
  the same kind of dictation flickered between ~4–6 variants and lost words.
- `./build.sh` succeeds with Xcode 26.3. The default Xcode 16.4 / Swift 6.1 toolchain cannot build
  this FluidAudio revision (`MLMultiArrayDataType has no member 'int8'`).
- No automated tests were added, by decision: the change only adds a user choice, and upstream's
  direction suggests the right default may change again.
- Not checked: other Macs, other macOS versions, other Parakeet models (Mini, Pico, v2, v3), power
  or speed impact of GPU beyond a quick timing.

## Remaining work for cleanup

1. Offer the FluidAudio commit to altic-dev/FluidAudio. Once merged there, point `Package.swift`,
   `Fluid.xcodeproj/project.pbxproj`, and both `Package.resolved` files back at altic-dev.
2. Decide the default. CPU is kept today, so affected users only benefit if they find the setting.
   Consider defaulting to CPU + GPU, or picking per OS, once more machines are tested.
3. File an upstream issue on FluidInference/FluidAudio. The repro harness (runs only the
   preprocessor, reports which frames came out as "no sound") is kept locally at
   `scratch/preprocessor-repro/main.swift` (ignored). Use a synthetic clip; the user's own
   recording is private and must not be attached.
4. Side findings from the same investigation, not addressed:
   - `ASRService.smartDiffUpdate` is a no-op (`stableWords + newWords` rebuilds the current words).
   - The default dictation prompt's "Delete ... incomplete beginnings" clause can delete an entire
     short/truncated transcript; one model nearly did.
   - AI cleanup still runs (and writes history) after a cancelled recording (`historyOnly` route).
   - "Faster Long Dictation" freezes finalized windows; a bad window decode becomes permanent and
     the final reuses it. Less important once the preprocessor is fixed, but still unguarded.
