import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        TabView {
            GeneralSettings(state: state)
                .tabItem { Label("General", systemImage: "gearshape") }
            SoundSettings(state: state)
                .tabItem { Label("Sound", systemImage: "speaker.wave.2") }
            VisualizerSettings(state: state)
                .tabItem { Label("Visualizer", systemImage: "rectangle.grid.3x2") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @ObservedObject var state: AppState
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Toggle("Enable Quiet Keys", isOn: $state.enabled)
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { on in
                    do {
                        if on { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }

            Section("Sounds") {
                Toggle("Key release sounds", isOn: $state.releaseSounds)
                Toggle("Sounds while a key repeats", isOn: $state.repeatSounds)
                Toggle("Mouse click sounds", isOn: $state.mouseClicks)
            }

            Section("Permission") {
                if state.hasPermission {
                    Label("Accessibility access granted",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    LabeledContent {
                        Button("Grant access") { state.requestPermission() }
                    } label: {
                        Text("Quiet Keys needs Accessibility access to hear keystrokes.")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}

// MARK: - Sound

private struct SoundSettings: View {
    @ObservedObject var state: AppState

    var body: some View {
        Form {
            Section("Switches") {
                ForEach(state.profileManager.brands, id: \.self) { brand in
                    DisclosureGroup(brand) {
                        ForEach(state.profileManager.profiles(for: brand)) { profile in
                            HStack {
                                Image(systemName: state.profileID == profile.id
                                    ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(state.profileID == profile.id
                                        ? Color.accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(profile.name)
                                    Text(profile.type)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    state.preview(profile)
                                } label: {
                                    Image(systemName: "play.circle")
                                }
                                .buttonStyle(.borderless)
                                .help("Preview")
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { state.profileID = profile.id }
                        }
                    }
                }
            }

            Section("Output") {
                LabeledContent("Volume") {
                    Slider(value: $state.volume, in: 0...1.2)
                }
                LabeledContent("Tone") {
                    Slider(value: $state.tone, in: -1...1) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("Dark").font(.caption)
                    } maximumValueLabel: {
                        Text("Bright").font(.caption)
                    }
                }
                Toggle("Spatial audio (pan by key position)",
                       isOn: $state.spatialAudio)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}

// MARK: - Visualizer

private struct VisualizerSettings: View {
    @ObservedObject var state: AppState

    var body: some View {
        Form {
            Toggle("Enable visualizer", isOn: $state.visualizerEnabled)
            Picker("Position", selection: $state.visualizerPositionRaw) {
                ForEach(VisualizerPosition.allCases) { pos in
                    Text(pos.rawValue).tag(pos.rawValue)
                }
            }
            .disabled(!state.visualizerEnabled)
            Text("A small on-screen keyboard lights up keys as you type. It never captures your input — it only mirrors what you press.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}

// MARK: - About

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
            Text("Quiet Keys")
                .font(.title2.bold())
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .foregroundStyle(.secondary)
            Text("Your keyboard, but better. Free and open source under the MIT License. No data collected, no network access, fully offline.")
                .multilineTextAlignment(.center)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)
            Link("github.com/quietapps/QuietKeys",
                 destination: URL(string: "https://github.com/quietapps/QuietKeys")!)
                .font(.callout)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
