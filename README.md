# quiet keys

**Your keyboard, but better.** A native macOS menu-bar app that plays realistic mechanical keyboard switch sounds on every keystroke and mouse click. Free, open source, and fully offline.

- **22 switch profiles** across IQUNIX, Lofree, Akko, Keychron, Aflion, Durock, Gateron, NovelKeys, Drop, Kailh, IBM, Topre, Alps — plus a quirky Lizard.
- **Ultra-low latency** — lock-free audio engine, 128-frame CoreAudio buffer, all samples preloaded. Nothing allocates on the audio thread.
- **Spatial audio** — keys on the left half of your keyboard play from the left speaker; keys on the right play from the right.
- **Reactive visualizer** — a floating mini keyboard that lights up keys as you press them. Follow-cursor or fixed positions.
- **Distinct press and release sounds**, per-key-class samples (space, return, backspace sound deeper), round-robin variants so no two keystrokes sound identical.
- **Mouse click sounds** for left, right, and middle buttons. Toggleable.
- **Type-to-hear demo** — built-in typing test with WPM, accuracy, and timer, plus a rendered keyboard that highlights every key.
- **Completely private** — no data collected, no accounts, no network access, no telemetry. The app never asks for any personal details.

Requires macOS 13 Ventura or later.

## Install

**GitHub Releases** — download the latest notarized `.dmg` from [Releases](../../releases), drag Quiet Keys to Applications.

**Homebrew** (optional cask):

```sh
brew install --cask quietapps/tap/quiet-keys
```

## Permissions setup

Quiet Keys listens for keystrokes system-wide through a **listen-only** CGEvent tap. macOS requires the Accessibility permission for this:

1. Launch Quiet Keys. The onboarding window opens automatically.
2. Click **Grant Accessibility access** — macOS shows the system prompt.
3. In **System Settings → Privacy & Security → Accessibility**, enable **Quiet Keys**.
4. The onboarding window detects the grant automatically and you're done.

Keystrokes are matched to a sound and immediately forgotten. Nothing is logged, stored, or transmitted — you can audit the input path in [`InputMonitor.swift`](QuietKeys/Input/InputMonitor.swift) and [`AppState.swift`](QuietKeys/App/AppState.swift).

If sounds stop after an OS update, re-toggle the permission (macOS occasionally invalidates event taps on major updates).

## Adding a switch profile

Profiles are drop-in sample folders — no code changes needed.

```
MyProfile/
├── manifest.json
├── default_down_1.wav   ← round-robin press variants
├── default_down_2.wav
├── default_up_1.wav     ← release variants
├── space_down_1.wav     ← optional per-key-class samples
├── return_down_1.wav
└── delete_down_1.wav
```

`manifest.json`:

```json
{
  "id": "mybrand-myswitch",
  "name": "My Switch",
  "brand": "MyBrand",
  "type": "tactile",
  "gain": 1.0,
  "keys": {
    "default": { "down": ["default_down_1.wav", "default_down_2.wav"],
                 "up":   ["default_up_1.wav"] },
    "space":   { "down": ["space_down_1.wav"], "up": [] }
  }
}
```

Drop the folder into `~/Library/Application Support/Quiet Keys/Profiles/` and relaunch — it appears in the switches picker grouped under its brand. Key classes fall back to `default` when omitted. Samples can be any sample rate/bit depth AVFoundation reads; they're converted to 48 kHz float internally.

To contribute a profile to the app itself, add the folder under `QuietKeys/Resources/Profiles/` (or add a parametric definition to `Tools/generate_samples.py`) and open a PR.

## Build from source

Requirements: Xcode 15+, [XcodeGen](https://github.com/yonaskolb/XcodeGen), Python 3 with `numpy` (sample generation only).

```sh
git clone https://github.com/quietapps/QuietKeys.git
cd QuietKeys
python3 Tools/generate_samples.py   # regenerate the sample library (optional; samples are committed)
xcodegen generate
xcodebuild -project QuietKeys.xcodeproj -scheme QuietKeys -configuration Release build
```

The built app lands in DerivedData; or open `QuietKeys.xcodeproj` in Xcode and run.

### Signing & notarization

Local development builds use ad-hoc signing (`CODE_SIGN_IDENTITY=-`). For distribution:

```sh
xcodebuild -project QuietKeys.xcodeproj -scheme QuietKeys -configuration Release \
  CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" build
xcrun notarytool submit QuietKeys.dmg --keychain-profile notary --wait
xcrun stapler staple QuietKeys.dmg
```

CI (`.github/workflows/release.yml`) builds every push and, when signing secrets are configured, produces a signed + notarized `.dmg` on tagged releases. Required repo secrets: `MACOS_CERTIFICATE_P12`, `MACOS_CERTIFICATE_PASSWORD`, `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID`, `NOTARY_PASSWORD`.

## Architecture

| Piece | File | Notes |
|---|---|---|
| Audio engine | `QuietKeys/Audio/AudioEngine.swift` | `AVAudioSourceNode` + 64-voice pool; SPSC lock-free trigger ring (C11 atomics in `Support/qk_atomics.h`); equal-power pan; shelving-EQ tone control |
| Sample loading | `QuietKeys/Audio/SampleBuffer.swift` | Preloads WAVs to contiguous float buffers at 48 kHz |
| Input | `QuietKeys/Input/InputMonitor.swift` | Listen-only CGEvent tap on a dedicated user-interactive thread |
| Key geometry | `QuietKeys/Input/KeyLayout.swift` | ANSI layout → pan position + visualizer/typing-test rendering |
| Profiles | `QuietKeys/Profiles/ProfileManager.swift` | Bundle + Application Support discovery, manifest decoding |
| UI | `QuietKeys/UI/` | Menu-bar dropdown, settings, visualizer panel, typing test, onboarding |
| Sample synthesis | `Tools/generate_samples.py` | Parametric physical model — every shipped sample is original |

All shipped samples are synthesized from parametric switch models in this repo — no recordings from other apps are used.

## Privacy

No data collected. No accounts. No network access. No telemetry or analytics. Fully offline. That's the whole policy.

## Feedback

Bug reports and ideas: [GitHub Issues](../../issues). Contributions: see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
