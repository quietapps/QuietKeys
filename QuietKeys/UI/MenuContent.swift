import SwiftUI

/// Native menu-bar dropdown: Control / Configure / App sections with real
/// submenus for Switches and Position, matching the standard macOS menu look.
struct MenuContent: View {
    @ObservedObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Section("Control") {
            Button {
                state.enabled.toggle()
            } label: {
                Label(state.enabled ? "Disable Quiet Keys" : "Enable Quiet Keys",
                      systemImage: state.enabled ? "checkmark.circle.fill" : "circle")
            }

            if !state.hasPermission {
                Button {
                    state.requestPermission()
                } label: {
                    Label("Grant Accessibility access…",
                          systemImage: "exclamationmark.triangle")
                }
            }
        }

        Section("Configure") {
            SettingsButton(title: "Sound", icon: "slider.horizontal.3")

            Menu {
                Picker("Switches", selection: $state.profileID) {
                    ForEach(state.profileManager.brands, id: \.self) { brand in
                        Section(brand) {
                            ForEach(state.profileManager.profiles(for: brand)) { profile in
                                Text(profile.name).tag(profile.id)
                            }
                        }
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Label("Switches", systemImage: "keyboard")
            }

            Button {
                state.visualizerEnabled.toggle()
            } label: {
                Label(state.visualizerEnabled ? "Disable Visualizer"
                                              : "Enable Visualizer",
                      systemImage: state.visualizerEnabled
                          ? "checkmark.circle.fill" : "rectangle.grid.3x2")
            }

            Menu {
                Picker("Position", selection: $state.visualizerPositionRaw) {
                    ForEach(VisualizerPosition.allCases) { pos in
                        Label(pos.rawValue, systemImage: pos.icon)
                            .tag(pos.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Label("Position", systemImage: "rectangle.inset.filled")
            }
        }

        Section("App") {
            Button {
                openWindow(id: "typing-test")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Typing Test", systemImage: "text.cursor")
            }

            SettingsButton()
                .keyboardShortcut(",", modifiers: .command)

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit Quiet Keys", systemImage: "xmark.circle")
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

}

/// Menu item that opens the Settings scene; supported action on 14+,
/// responder-chain fallback on 13.
struct SettingsButton: View {
    var title = "Settings…"
    var icon = "gearshape"

    var body: some View {
        if #available(macOS 14.0, *) {
            SettingsButton14(title: title, icon: icon)
        } else {
            Button {
                SettingsOpener.open()
            } label: {
                Label(title, systemImage: icon)
            }
        }
    }
}

@available(macOS 14.0, *)
private struct SettingsButton14: View {
    let title: String
    let icon: String
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        } label: {
            Label(title, systemImage: icon)
        }
    }
}

/// macOS 13 fallback: the legacy responder-chain selector.
enum SettingsOpener {
    @MainActor
    static func open() {
        NSApp.activate(ignoringOtherApps: true)
        if NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            return
        }
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
}
