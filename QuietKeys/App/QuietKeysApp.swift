import SwiftUI

@main
struct QuietKeysApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(state: state)
        } label: {
            Image(systemName: state.enabled ? "keyboard.fill" : "keyboard")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(state: state)
        }

        Window("Typing Test", id: "typing-test") {
            TypingTestView(state: state)
        }
        .defaultSize(width: 720, height: 540)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar app: no Dock icon.
        NSApp.setActivationPolicy(.accessory)

        let state = AppState.shared
        if !state.onboarded || !state.hasPermission {
            showOnboarding(state: state)
        }
    }

    private func showOnboarding(state: AppState) {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: OnboardingView(state: state))
        window.center()
        onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
