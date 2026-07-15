import SwiftUI

/// First-run flow: explain the permission, request it, confirm, pick a sound.
struct OnboardingView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color.accentColor)

            Text("Welcome to Quiet Keys")
                .font(.title.bold())

            Text("Quiet Keys plays a mechanical switch sound for every key you press, in any app. To hear your keystrokes it needs macOS Accessibility access.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)

            VStack(alignment: .leading, spacing: 10) {
                bullet("lock.shield", "Keystrokes are matched to sounds and immediately forgotten — nothing is logged or stored.")
                bullet("wifi.slash", "Fully offline. No network access, no analytics, no accounts.")
                bullet("doc.text.magnifyingglass", "Open source under the MIT License — audit every line.")
            }
            .frame(maxWidth: 420)

            if state.hasPermission {
                Label("Access granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button("Start typing") {
                    state.onboarded = true
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            } else {
                Button("Grant Accessibility access") {
                    state.requestPermission()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                Text("System Settings → Privacy & Security → Accessibility → enable Quiet Keys. This window updates automatically once access is granted.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
        }
        .padding(36)
        .frame(width: 520)
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(Color.accentColor)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
