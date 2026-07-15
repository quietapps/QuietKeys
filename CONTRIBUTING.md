# Contributing to Quiet Keys

Thanks for helping. Quiet Keys stays small, fast, and private — contributions that keep it that way are very welcome.

## Ground rules

- **No network code.** The app is fully offline by design. PRs adding any network access, telemetry, or analytics will be declined.
- **Nothing on the audio thread.** No allocation, no locks, no ObjC messaging inside the render callback. The trigger path is a lock-free SPSC ring — keep it that way.
- **macOS 13+.** Don't use newer-only API without an availability fallback.
- **MIT-compatible assets only.** Sound samples must be original recordings you made or synthesized output from `Tools/generate_samples.py`. Never copy samples from other apps.

## Dev setup

```sh
brew install xcodegen
git clone https://github.com/quietapps/QuietKeys.git && cd QuietKeys
xcodegen generate
open QuietKeys.xcodeproj
```

Samples are committed; regenerate with `python3 Tools/generate_samples.py` (needs `numpy`).

## Adding a switch profile

Preferred: add a parametric definition to `PROFILES` in `Tools/generate_samples.py` and regenerate — keeps the whole library reproducible. Alternatively contribute recorded WAVs (that you own) as a folder under `QuietKeys/Resources/Profiles/` with a `manifest.json` (schema in the README).

Listen before you PR: use the in-app typing test to audition your profile at speed.

## Pull requests

1. Branch from `main`, one topic per PR.
2. Make sure `xcodebuild -project QuietKeys.xcodeproj -scheme QuietKeys build` passes.
3. Describe *why*, not only what.
4. UI changes: attach a screenshot or short clip.

## Reporting bugs

Open a [GitHub Issue](../../issues) with macOS version, app version, and steps to reproduce. For audio glitches include your output device and sample rate (Audio MIDI Setup).
