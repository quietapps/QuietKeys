import AppKit
import Combine
import SwiftUI

/// Central coordinator: wires the input monitor to the audio engine, owns the
/// active profile, and persists user settings. All state is local; the app
/// makes no network requests and collects nothing.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: - Persisted settings
    //
    // Not @AppStorage: SwiftUI bindings write through the wrapper's projected
    // value, which bypasses didSet — profile changes never reached the engine.
    // @Published setters always run, so persist + apply happens in didSet.

    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: "enabled"); applyEnabled() }
    }
    @Published var profileID: String {
        didSet { defaults.set(profileID, forKey: "profileID"); loadActiveProfile() }
    }
    @Published var volume: Double {
        didSet { defaults.set(volume, forKey: "volume"); engine.volume = Float(volume) }
    }
    @Published var tone: Double {
        didSet { defaults.set(tone, forKey: "tone"); engine.configureTone(Float(tone)) }
    }
    @Published var spatialAudio: Bool {
        didSet { defaults.set(spatialAudio, forKey: "spatialAudio") }
    }
    @Published var mouseClicks: Bool {
        didSet { defaults.set(mouseClicks, forKey: "mouseClicks") }
    }
    @Published var releaseSounds: Bool {
        didSet { defaults.set(releaseSounds, forKey: "releaseSounds") }
    }
    @Published var repeatSounds: Bool {
        didSet { defaults.set(repeatSounds, forKey: "repeatSounds") }
    }
    @Published var visualizerEnabled: Bool {
        didSet {
            defaults.set(visualizerEnabled, forKey: "visualizerEnabled")
            visualizer.setEnabled(visualizerEnabled)
        }
    }
    @Published var visualizerPositionRaw: String {
        didSet {
            defaults.set(visualizerPositionRaw, forKey: "visualizerPosition")
            visualizer.position = visualizerPosition
        }
    }
    @Published var onboarded: Bool {
        didSet { defaults.set(onboarded, forKey: "onboarded") }
    }

    private let defaults = UserDefaults.standard

    var visualizerPosition: VisualizerPosition {
        VisualizerPosition(rawValue: visualizerPositionRaw) ?? .bottomCenter
    }

    // MARK: - Runtime

    let engine = AudioEngine()
    let monitor = InputMonitor()
    let profileManager = ProfileManager()
    let visualizer = VisualizerController()

    @Published private(set) var hasPermission = InputMonitor.hasPermission

    /// UI feed of key events (main thread) for the visualizer + typing test.
    let keyEvents = PassthroughSubject<InputMonitor.KeyEvent, Never>()

    /// Bank handoff to the tap thread — guarded by a lock (never touched by
    /// the audio render thread, which only sees raw buffer pointers).
    private let bankBox = BankBox()

    private var permissionTimer: Timer?

    private init() {
        // The tap thread reads settings straight from UserDefaults; without
        // registered defaults an unset key reads as false and mutes the app.
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "enabled": true,
            "profileID": "gateron-ink-black",
            "volume": 0.8,
            "tone": 0.0,
            "spatialAudio": true,
            "mouseClicks": true,
            "releaseSounds": true,
            "repeatSounds": true,
            "visualizerEnabled": false,
            "visualizerPosition": VisualizerPosition.bottomCenter.rawValue,
            "onboarded": false,
        ])

        // didSet does not fire during init — apply everything explicitly below.
        enabled = defaults.bool(forKey: "enabled")
        profileID = defaults.string(forKey: "profileID") ?? "gateron-ink-black"
        volume = defaults.double(forKey: "volume")
        tone = defaults.double(forKey: "tone")
        spatialAudio = defaults.bool(forKey: "spatialAudio")
        mouseClicks = defaults.bool(forKey: "mouseClicks")
        releaseSounds = defaults.bool(forKey: "releaseSounds")
        repeatSounds = defaults.bool(forKey: "repeatSounds")
        visualizerEnabled = defaults.bool(forKey: "visualizerEnabled")
        visualizerPositionRaw = defaults.string(forKey: "visualizerPosition")
            ?? VisualizerPosition.bottomCenter.rawValue
        onboarded = defaults.bool(forKey: "onboarded")

        engine.volume = Float(volume)
        engine.configureTone(Float(tone))
        visualizer.position = visualizerPosition
        visualizer.setEnabled(visualizerEnabled)

        monitor.onKey = { [weak self] event in
            self?.handleKey(event)          // tap thread
        }
        monitor.onMouse = { [weak self] event in
            self?.handleMouse(event)        // tap thread
        }

        loadActiveProfile()
        applyEnabled()
        watchPermission()
    }

    var activeProfile: Profile? {
        profileManager.profile(id: profileID)
    }

    // MARK: - Enable / permission

    private func applyEnabled() {
        if enabled && hasPermission {
            engine.start()
            monitor.start()
        } else {
            monitor.stop()
            engine.stop()
        }
    }

    func requestPermission() {
        InputMonitor.requestPermission()
    }

    /// Accessibility grants arrive out-of-band — poll until trusted.
    private func watchPermission() {
        guard !hasPermission else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5,
                                               repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let trusted = InputMonitor.hasPermission
                if trusted != self.hasPermission {
                    self.hasPermission = trusted
                    self.applyEnabled()
                }
                if trusted {
                    self.permissionTimer?.invalidate()
                    self.permissionTimer = nil
                }
            }
        }
    }

    // MARK: - Profile

    private func loadActiveProfile() {
        guard let profile = activeProfile ?? profileManager.profiles.first else { return }
        let bank = SampleBank(profile: profile,
                              mouseManifest: profileManager.mouseManifest,
                              sampleRate: AudioEngine.sampleRate)
        engine.retain(bank: bank)
        bankBox.set(bank)
    }

    /// Audition a profile without activating it.
    func preview(_ profile: Profile) {
        engine.start()
        let bank = SampleBank(profile: profile,
                              mouseManifest: nil,
                              sampleRate: AudioEngine.sampleRate)
        engine.retain(bank: bank)
        let pattern: [(SampleBank.KeyClass, Float, Double)] = [
            (.default, -0.4, 0.00), (.default, 0.1, 0.11), (.default, 0.4, 0.23),
            (.space, 0.0, 0.36), (.return, 0.55, 0.50),
        ]
        for (keyClass, pan, delay) in pattern {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                if let buffer = bank.nextBuffer(for: keyClass, isDown: true) {
                    self.engine.trigger(buffer: buffer,
                                        gain: bank.gain,
                                        pan: self.spatialAudio ? pan : 0)
                }
            }
        }
    }

    // MARK: - Event handling (tap thread)

    nonisolated private func handleKey(_ event: InputMonitor.KeyEvent) {
        // Settings are read straight from UserDefaults — plain value loads,
        // safe off the main actor and cheap enough for the tap thread.
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "enabled") else { return }
        if event.isRepeat && !defaults.bool(forKey: "repeatSounds") { return }
        if !event.isDown && !defaults.bool(forKey: "releaseSounds") { return }

        guard let bank = bankBox.get(),
              let buffer = bank.nextBuffer(for: KeyLayout.keyClass(for: event.keyCode),
                                           isDown: event.isDown)
        else { return }

        let pan = defaults.bool(forKey: "spatialAudio")
            ? KeyLayout.pan(for: event.keyCode) : 0
        engine.trigger(buffer: buffer, gain: bank.gain, pan: pan)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.keyEvents.send(event)
            self.visualizer.keyEvent(event)
        }
    }

    nonisolated private func handleMouse(_ event: InputMonitor.MouseEvent) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "enabled"),
              defaults.bool(forKey: "mouseClicks") else { return }

        guard let bank = bankBox.get() else { return }

        let (button, isDown): (MouseButton, Bool)
        switch event {
        case .left(let down): (button, isDown) = (.mouse_left, down)
        case .right(let down): (button, isDown) = (.mouse_right, down)
        case .middle(let down): (button, isDown) = (.mouse_middle, down)
        }
        if !isDown && !defaults.bool(forKey: "releaseSounds") { return }
        guard let buffer = bank.nextMouseBuffer(for: button, isDown: isDown) else { return }
        engine.trigger(buffer: buffer, gain: 0.9, pan: 0)
    }
}

/// Thread-safe holder for the active sample bank, shared between the main
/// actor (profile swaps) and the event-tap thread (reads on every keystroke).
final class BankBox: @unchecked Sendable {
    private let lock = NSLock()
    private var bank: SampleBank?

    func set(_ newBank: SampleBank?) {
        lock.lock()
        bank = newBank
        lock.unlock()
    }

    func get() -> SampleBank? {
        lock.lock()
        defer { lock.unlock() }
        return bank
    }
}
