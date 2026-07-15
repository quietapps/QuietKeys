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
                Label {
                    Text(state.enabled ? "Disable Quiet Keys" : "Enable Quiet Keys")
                } icon: {
                    StatusIcon(on: state.enabled)
                }
            }

            if state.hasPermission {
                Label {
                    Text("Accessibility access granted")
                } icon: {
                    ColoredSymbol("checkmark.circle.fill", color: .systemGreen)
                }
            } else {
                Button {
                    state.requestPermission()
                } label: {
                    Label {
                        Text("Grant Accessibility access…")
                    } icon: {
                        ColoredSymbol("exclamationmark.triangle.fill",
                                      color: .systemOrange)
                    }
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
                Label {
                    Text(state.visualizerEnabled ? "Disable Visualizer"
                                                 : "Enable Visualizer")
                } icon: {
                    StatusIcon(on: state.visualizerEnabled)
                }
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

/// Green filled circle when on, gray hollow circle when off. Rendered as a
/// non-template NSImage so the native menu keeps the color instead of
/// flattening it to the standard menu tint.
private struct StatusIcon: View {
    let on: Bool

    var body: some View {
        ColoredSymbol(on ? "circle.fill" : "circle",
                      color: on ? .systemGreen : .tertiaryLabelColor)
    }
}

/// SF Symbol drawn in a fixed color that survives native menu rendering.
private struct ColoredSymbol: View {
    let name: String
    let color: NSColor

    init(_ name: String, color: NSColor) {
        self.name = name
        self.color = color
    }

    var body: some View {
        Image(nsImage: Self.image(name: name, color: color))
    }

    private static func image(name: String, color: NSColor) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            .applying(.init(paletteColors: [color]))
        guard let base = NSImage(systemSymbolName: name,
                                 accessibilityDescription: nil),
              let symbol = base.withSymbolConfiguration(config) else {
            return NSImage()
        }
        symbol.isTemplate = false
        return symbol
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
