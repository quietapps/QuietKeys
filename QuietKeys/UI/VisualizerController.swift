import AppKit
import SwiftUI

enum VisualizerPosition: String, CaseIterable, Identifiable {
    case followCursor = "Follow Cursor"
    case topLeft = "Top Left"
    case topCenter = "Top Center"
    case topRight = "Top Right"
    case bottomLeft = "Bottom Left"
    case bottomCenter = "Bottom Center"
    case bottomRight = "Bottom Right"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .followCursor: return "cursorarrow"
        case .topLeft: return "rectangle.inset.topleft.filled"
        case .topCenter: return "rectangle.tophalf.inset.filled"
        case .topRight: return "rectangle.inset.topright.filled"
        case .bottomLeft: return "rectangle.inset.bottomleft.filled"
        case .bottomCenter: return "rectangle.bottomhalf.inset.filled"
        case .bottomRight: return "rectangle.inset.bottomright.filled"
        }
    }

    /// Migrates values stored by earlier builds ("Bottom center" style).
    init?(stored: String) {
        if let exact = VisualizerPosition(rawValue: stored) {
            self = exact
            return
        }
        if let match = VisualizerPosition.allCases.first(where: {
            $0.rawValue.lowercased() == stored.lowercased()
        }) {
            self = match
            return
        }
        return nil
    }
}

/// Floating, click-through mini keyboard that lights up pressed keys.
@MainActor
final class VisualizerController: ObservableObject {
    @Published var pressedKeys: Set<Int> = []

    var position: VisualizerPosition = .bottomCenter {
        didSet { reposition() }
    }

    private var panel: NSPanel?
    private let size = NSSize(width: 340, height: 128)

    func setEnabled(_ enabled: Bool) {
        if enabled { show() } else { hide() }
    }

    func keyEvent(_ event: InputMonitor.KeyEvent) {
        guard panel != nil else { return }
        let code = Int(event.keyCode)
        if event.isDown {
            pressedKeys.insert(code)
        } else {
            pressedKeys.remove(code)
        }
        if position == .followCursor { reposition() }
    }

    private func show() {
        guard panel == nil else { return }
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                    .stationary]
        panel.contentView = NSHostingView(
            rootView: MiniKeyboardView().environmentObject(self))
        self.panel = panel
        reposition()
        panel.orderFrontRegardless()
    }

    private func hide() {
        panel?.orderOut(nil)
        panel = nil
        pressedKeys.removeAll()
    }

    private func reposition() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first {
            NSMouseInRect(mouse, $0.frame, false)
        } ?? NSScreen.main
        guard let screen else { return }
        let f = screen.visibleFrame
        let margin: CGFloat = 24
        var origin: NSPoint
        switch position {
        case .followCursor:
            origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y + 28)
            origin.x = max(f.minX + 8, min(origin.x, f.maxX - size.width - 8))
            origin.y = min(origin.y, f.maxY - size.height - 8)
        case .bottomLeft:
            origin = NSPoint(x: f.minX + margin, y: f.minY + margin)
        case .bottomCenter:
            origin = NSPoint(x: f.midX - size.width / 2, y: f.minY + margin)
        case .bottomRight:
            origin = NSPoint(x: f.maxX - size.width - margin, y: f.minY + margin)
        case .topLeft:
            origin = NSPoint(x: f.minX + margin,
                             y: f.maxY - size.height - margin)
        case .topCenter:
            origin = NSPoint(x: f.midX - size.width / 2,
                             y: f.maxY - size.height - margin)
        case .topRight:
            origin = NSPoint(x: f.maxX - size.width - margin,
                             y: f.maxY - size.height - margin)
        }
        panel.setFrameOrigin(origin)
    }
}

/// The rendered mini keyboard. Dark surface, quiet-blue key lights.
struct MiniKeyboardView: View {
    @EnvironmentObject var controller: VisualizerController

    var body: some View {
        KeyboardShapeView(pressedKeys: controller.pressedKeys,
                          keySpacing: 2.5,
                          cornerRadius: 3)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.043, green: 0.051, blue: 0.067)
                        .opacity(0.92))
            )
            .padding(4)
    }
}

/// Shared keyboard renderer used by the visualizer and the typing test.
struct KeyboardShapeView: View {
    let pressedKeys: Set<Int>
    var keySpacing: CGFloat = 4
    var cornerRadius: CGFloat = 5
    var showLabels: Bool = false

    private static let quietBlue = Color(red: 0.118, green: 0.533, blue: 0.898)

    var body: some View {
        GeometryReader { geo in
            let rows = KeyLayout.ansiRows
            let rowCount = CGFloat(rows.count)
            let rowHeight = (geo.size.height - keySpacing * (rowCount - 1)) / rowCount
            VStack(spacing: keySpacing) {
                ForEach(0..<rows.count, id: \.self) { r in
                    let row = rows[r]
                    let units = row.reduce(CGFloat(0)) { $0 + $1.width }
                    let unit = (geo.size.width - keySpacing * CGFloat(row.count - 1)) / units
                    HStack(spacing: keySpacing) {
                        ForEach(0..<row.count, id: \.self) { k in
                            let key = row[k]
                            let pressed = pressedKeys.contains(key.code)
                            RoundedRectangle(cornerRadius: cornerRadius,
                                             style: .continuous)
                                .fill(pressed ? Self.quietBlue
                                              : Color.white.opacity(0.10))
                                .overlay {
                                    if showLabels {
                                        Text(key.label)
                                            .font(.system(size: min(rowHeight * 0.34, 11),
                                                          weight: .medium))
                                            .foregroundStyle(
                                                pressed ? Color.white
                                                        : Color.white.opacity(0.55))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.5)
                                    }
                                }
                                .frame(width: unit * key.width, height: rowHeight)
                                .animation(.easeOut(duration: 0.12), value: pressed)
                        }
                    }
                }
            }
        }
    }
}
