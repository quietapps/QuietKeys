import SwiftUI

/// The menu-bar dropdown: every core control one click away.
struct MenuContent: View {
    @ObservedObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            section("Control")
            Toggle(isOn: $state.enabled) {
                Label("Enable Quiet Keys", systemImage: "keyboard")
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            if !state.hasPermission {
                PermissionNudge(state: state)
            }

            Divider().padding(.vertical, 4)
            section("Sound")

            Picker(selection: $state.profileID) {
                ForEach(state.profileManager.brands, id: \.self) { brand in
                    Section(brand) {
                        ForEach(state.profileManager.profiles(for: brand)) { profile in
                            Text(profile.name).tag(profile.id)
                        }
                    }
                }
            } label: {
                Label("Switches", systemImage: "square.grid.3x2")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            HStack(spacing: 8) {
                Label("Volume", systemImage: "speaker.wave.2")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                Slider(value: $state.volume, in: 0...1.2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            HStack(spacing: 8) {
                Label("Tone", systemImage: "slider.horizontal.3")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                Slider(value: $state.tone, in: -1...1)
                    .help("Darker to brighter")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Divider().padding(.vertical, 4)

            Toggle(isOn: $state.visualizerEnabled) {
                Label("Enable Visualizer", systemImage: "rectangle.grid.3x2")
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Picker(selection: $state.visualizerPositionRaw) {
                ForEach(VisualizerPosition.allCases) { pos in
                    Text(pos.rawValue).tag(pos.rawValue)
                }
            } label: {
                Label("Position", systemImage: "rectangle.bottomthird.inset.filled")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .disabled(!state.visualizerEnabled)

            Divider().padding(.vertical, 4)
            section("App")

            MenuRow(title: "Typing test", systemImage: "text.cursor") {
                openWindow(id: "typing-test")
                NSApp.activate(ignoringOtherApps: true)
            }
            MenuRow(title: "Settings…", systemImage: "gearshape",
                    shortcut: "⌘,") {
                SettingsOpener.open()
            }
            MenuRow(title: "Quit Quiet Keys", systemImage: "power",
                    shortcut: "⌘Q") {
                NSApp.terminate(nil)
            }
        }
        .padding(.vertical, 8)
        .frame(width: 280)
    }

    private func section(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.8)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
    }
}

/// Opens the SwiftUI Settings scene on macOS 13 and 14+ alike.
enum SettingsOpener {
    static func open() {
        NSApp.activate(ignoringOtherApps: true)
        // macOS 14+
        if NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            return
        }
        // macOS 13
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
}

private struct MenuRow: View {
    let title: String
    let systemImage: String
    var shortcut: String?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(hovering ? Color.primary.opacity(0.07) : .clear)
        .onHover { hovering = $0 }
    }
}

private struct PermissionNudge: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Accessibility permission needed to hear keystrokes.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Button("Grant access") {
                state.requestPermission()
            }
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(Color.orange.opacity(0.12)))
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}
