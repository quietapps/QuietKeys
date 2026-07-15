# Changelog

All notable changes to Quiet Keys are documented here.

Format: version **X.Y.Z**, build **N** — newest first.

---

## 1.0.0 — build 1 (2026-07-15)

Initial release.

### Added

- **22 switch profiles** across IQUNIX, Lofree, Akko, Keychron, Aflion, Durock, Gateron, NovelKeys, Drop, Kailh, IBM, Topre, Alps — plus a quirky Lizard; every sample synthesized from parametric switch models, no recordings from other apps
- **Ultra-low-latency audio engine** — lock-free `AVAudioSourceNode` with a 64-voice pool, 128-frame CoreAudio buffer, all samples preloaded; nothing allocates on the audio thread
- **Spatial audio** — keys pan by their physical position on an ANSI layout; left keys play from the left speaker, right keys from the right
- **Distinct press and release sounds** — per-key-class samples (space, return, and backspace sound deeper) with round-robin variants so no two keystrokes sound identical
- **Mouse click sounds** for left, right, and middle buttons; toggleable
- **Reactive visualizer** — a floating mini keyboard that lights up keys as you type; follow-cursor or fixed screen positions
- **Typing test** — built-in demo window with WPM, accuracy, timer, and a rendered keyboard that highlights every key
- **Sound settings** — searchable switch picker with type filter (linear/tactile/clicky), instant preview on selection, volume, dark–bright tone control, spatial audio toggle
- **Menu bar dropdown** — native menu with colored status indicators: green when enabled, checkmark when Accessibility is granted
- **Custom switch profiles** — drop a folder with `manifest.json` and WAV samples into `~/Library/Application Support/Quiet Keys/Profiles/`, no rebuild needed
- **Launch at login**, onboarding flow with automatic permission detection
- **Fully private** — listen-only CGEvent tap, no data collected, no accounts, no network access, no telemetry
