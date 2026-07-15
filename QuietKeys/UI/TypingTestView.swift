import Combine
import SwiftUI

/// Type-to-hear demo: a typing test with WPM / accuracy / timer readouts and
/// a rendered keyboard that highlights every pressed key, so users can
/// audition a switch profile with their own hands.
struct TypingTestView: View {
    @ObservedObject var state: AppState

    private static let prompts = [
        "The quick brown fox jumps over the lazy dog while the rain settles quietly on the window.",
        "Good tools disappear into the work. You notice them only when they are gone.",
        "Typing should feel like something. Every key down, a small satisfying answer back.",
        "Slow is smooth and smooth is fast. Find a rhythm and let the sound carry it.",
    ]

    @State private var prompt = TypingTestView.prompts[0]
    @State private var typed = ""
    @State private var startedAt: Date?
    @State private var finishedAt: Date?
    @State private var errorCount = 0
    @State private var prevTypedCount = 0
    @State private var pressedKeys: Set<Int> = []
    @State private var now = Date()
    @FocusState private var focused: Bool

    private let clock = Timer.publish(every: 0.25, on: .main, in: .common)
        .autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            header
            statsBar
            promptView
            keyboard
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 480)
        .onReceive(clock) { now = $0 }
        .onReceive(state.keyEvents) { event in
            let code = Int(event.keyCode)
            if event.isDown { pressedKeys.insert(code) }
            else { pressedKeys.remove(code) }
        }
        .onAppear { focused = true }
    }

    private var header: some View {
        HStack {
            Text("Type to hear")
                .font(.title2.bold())
            Spacer()
            Picker("Switch", selection: $state.profileID) {
                ForEach(state.profileManager.brands, id: \.self) { brand in
                    Section(brand) {
                        ForEach(state.profileManager.profiles(for: brand)) { p in
                            Text("\(brand) \(p.name)").tag(p.id)
                        }
                    }
                }
            }
            .frame(maxWidth: 280)
            Button("Restart") { restart() }
                .keyboardShortcut("r", modifiers: .command)
        }
    }

    private var statsBar: some View {
        HStack(spacing: 24) {
            stat("WPM", wpmText)
            stat("Accuracy", accuracyText)
            stat("Time", timeText)
            Spacer()
            if finishedAt != nil {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(Color.primary.opacity(0.05)))
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .monospacedDigit()
        }
    }

    private var promptView: some View {
        VStack(alignment: .leading, spacing: 10) {
            promptText
                .font(.system(size: 17, design: .monospaced))
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("Start typing…", text: $typed, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 17, design: .monospaced))
                .focused($focused)
                .disabled(finishedAt != nil)
                .onChange(of: typed) { newValue in
                    handleTyped(newValue)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.15)))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(Color.primary.opacity(0.03)))
    }

    private var promptText: Text {
        var result = Text("")
        let promptChars = Array(prompt)
        let typedChars = Array(typed)
        for (i, ch) in promptChars.enumerated() {
            let s = String(ch)
            if i < typedChars.count {
                result = result + Text(s)
                    .foregroundColor(typedChars[i] == ch ? .green : .red)
            } else if i == typedChars.count {
                result = result + Text(s).underline().foregroundColor(.primary)
            } else {
                result = result + Text(s).foregroundColor(.secondary)
            }
        }
        return result
    }

    private var keyboard: some View {
        KeyboardShapeView(pressedKeys: pressedKeys,
                          keySpacing: 4,
                          cornerRadius: 5,
                          showLabels: true)
            .frame(maxHeight: 190)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.043, green: 0.051, blue: 0.067)))
    }

    // MARK: - Logic

    private func handleTyped(_ value: String) {
        if startedAt == nil && !value.isEmpty { startedAt = Date() }
        // Count fresh mistakes only (compare last char typed).
        let typedChars = Array(value)
        let promptChars = Array(prompt)
        if typedChars.count > prevTypedCount,
           let last = typedChars.indices.last, last < promptChars.count,
           typedChars[last] != promptChars[last] {
            errorCount += 1
        }
        prevTypedCount = typedChars.count
        if typedChars.count >= promptChars.count {
            finishedAt = Date()
        }
    }

    private func restart() {
        var next = Self.prompts.randomElement() ?? Self.prompts[0]
        if Self.prompts.count > 1 {
            while next == prompt {
                next = Self.prompts.randomElement() ?? next
            }
        }
        prompt = next
        typed = ""
        prevTypedCount = 0
        startedAt = nil
        finishedAt = nil
        errorCount = 0
        focused = true
    }

    private var elapsed: TimeInterval {
        guard let startedAt else { return 0 }
        return (finishedAt ?? now).timeIntervalSince(startedAt)
    }

    private var wpmText: String {
        guard elapsed > 1 else { return "—" }
        let words = Double(typed.count) / 5.0
        return String(format: "%.0f", words / (elapsed / 60))
    }

    private var accuracyText: String {
        guard !typed.isEmpty else { return "—" }
        let total = typed.count + errorCount
        let pct = 100.0 * Double(typed.count) / Double(max(total, 1))
        return String(format: "%.0f%%", min(pct, 100))
    }

    private var timeText: String {
        let s = Int(elapsed)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
