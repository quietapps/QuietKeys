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
    @State private var search = ""
    @State private var typeFilter = "All"

    private var types: [String] {
        var seen = Set<String>()
        return ["All"] + state.profileManager.profiles
            .map(\.type.capitalized)
            .filter { seen.insert($0).inserted }
            .sorted()
    }

    /// Brands that still have at least one profile after search + type filter,
    /// in discovery order, paired with their filtered profiles.
    private var filteredGroups: [(brand: String, profiles: [Profile])] {
        state.profileManager.brands.compactMap { brand in
            let profiles = state.profileManager.profiles(for: brand).filter {
                matches($0)
            }
            return profiles.isEmpty ? nil : (brand, profiles)
        }
    }

    private func matches(_ profile: Profile) -> Bool {
        if typeFilter != "All",
           profile.type.caseInsensitiveCompare(typeFilter) != .orderedSame {
            return false
        }
        guard !search.isEmpty else { return true }
        return profile.name.localizedCaseInsensitiveContains(search)
            || profile.brand.localizedCaseInsensitiveContains(search)
            || profile.type.localizedCaseInsensitiveContains(search)
    }

    var body: some View {
        VStack(spacing: 0) {
            SelectedSwitchCard(state: state)
                .padding([.horizontal, .top], 16)

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search switches", text: $search)
                        .textFieldStyle(.plain)
                    if !search.isEmpty {
                        Button {
                            search = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(.quaternary.opacity(0.5),
                            in: RoundedRectangle(cornerRadius: 6))

                Picker("", selection: $typeFilter) {
                    ForEach(types, id: \.self) { Text($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            ScrollViewReader { proxy in
                List {
                    ForEach(filteredGroups, id: \.brand) { group in
                        Section {
                            ForEach(group.profiles) { profile in
                                SwitchRow(profile: profile,
                                          selected: state.profileID == profile.id,
                                          select: {
                                              state.profileID = profile.id
                                              state.preview(profile)
                                          },
                                          preview: { state.preview(profile) })
                                    .id(profile.id)
                            }
                        } header: {
                            Text(group.brand)
                        }
                    }

                    if filteredGroups.isEmpty {
                        Text("No switches match.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                    }
                }
                .listStyle(.inset)
                .frame(height: 240)
                .onAppear { proxy.scrollTo(state.profileID, anchor: .center) }
            }

            Divider()

            Form {
                Section("Output") {
                    LabeledContent("Volume") {
                        Slider(value: $state.volume, in: 0...1.2) {
                            EmptyView()
                        } minimumValueLabel: {
                            Image(systemName: "speaker.fill")
                                .foregroundStyle(.secondary)
                        } maximumValueLabel: {
                            Image(systemName: "speaker.wave.3.fill")
                                .foregroundStyle(.secondary)
                        }
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
            .scrollDisabled(true)
            .frame(height: 190)
        }
    }
}

/// Always-visible summary of the active switch with a preview button, so the
/// current choice never has to be hunted for in the list.
private struct SelectedSwitchCard: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "keyboard.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.profileManager.profile(id: state.profileID)?.name
                     ?? "No switch selected")
                    .font(.headline)
                if let profile = state.profileManager.profile(id: state.profileID) {
                    Text("\(profile.brand) · \(profile.type.capitalized)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let profile = state.profileManager.profile(id: state.profileID) {
                Button {
                    state.preview(profile)
                } label: {
                    Label("Preview", systemImage: "play.fill")
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.4),
                    in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct SwitchRow: View {
    let profile: Profile
    let selected: Bool
    let select: () -> Void
    let preview: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? AnyShapeStyle(Color.accentColor)
                                          : AnyShapeStyle(.quaternary))
            Text(profile.name)
            Text(profile.type.capitalized)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.quaternary.opacity(0.5), in: Capsule())
            Spacer()
            Button(action: preview) {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
            .help("Preview")
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
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
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
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
