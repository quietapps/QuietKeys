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

    /// Cursor is over the panel — reveals the close and resize controls.
    @Published var hovering = false

    /// Show key legends on the mini keyboard.
    @Published var showLabels = false

    /// Restored at launch without side effects; user changes go through
    /// `setPosition`, which also discards any dragged-to position.
    var position: VisualizerPosition = .bottomCenter

    func setPosition(_ newPosition: VisualizerPosition) {
        position = newPosition
        clearCustomOrigin()
        reposition()
    }

    private var panel: NSPanel?
    private var mouseMonitors: [Any] = []

    /// Base size — also the minimum. Resizing scales up from here.
    private static let baseSize = NSSize(width: 340, height: 128)
    private static let maxScale: CGFloat = 2.5

    private(set) var scale: CGFloat =
        max(1, min(maxScale,
                   CGFloat(UserDefaults.standard.double(forKey: "visualizerScale"))))

    private var size: NSSize {
        NSSize(width: Self.baseSize.width * scale,
               height: Self.baseSize.height * scale)
    }

    /// Where the user dragged the panel, if anywhere. Overrides the preset
    /// position (except Follow Cursor, which recomputes on every key).
    private var customOrigin: NSPoint? = {
        let d = UserDefaults.standard
        guard d.bool(forKey: "visualizerHasCustomOrigin") else { return nil }
        return NSPoint(x: d.double(forKey: "visualizerOriginX"),
                       y: d.double(forKey: "visualizerOriginY"))
    }()

    /// True while the resize handle is being dragged — hover tracking must
    /// not flip the panel back to click-through mid-gesture.
    var resizing = false

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
        startHoverTracking()
    }

    private func hide() {
        stopHoverTracking()
        panel?.orderOut(nil)
        panel = nil
        pressedKeys.removeAll()
        hovering = false
    }

    // MARK: - Hover / close button

    /// The panel is click-through, so no tracking areas or hover events reach
    /// it. Watch global mouse movement instead: cursor over the panel reveals
    /// the close button, and only the button's corner accepts clicks so the
    /// rest of the keyboard never swallows input meant for windows below.
    private func startHoverTracking() {
        let handler: @Sendable (NSEvent) -> Void = { _ in
            Task { @MainActor [weak self] in self?.updateHover() }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved], handler: handler) {
            mouseMonitors.append(global)
        }
        // Once the corner is clickable, moves over it arrive as local events.
        mouseMonitors.append(NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved]) { event in
            handler(event)
            return event
        } as Any)
    }

    private func stopHoverTracking() {
        for monitor in mouseMonitors { NSEvent.removeMonitor(monitor) }
        mouseMonitors.removeAll()
    }

    private func updateHover() {
        guard let panel, !resizing else { return }
        let inside = panel.frame.contains(NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !inside
        if inside != hovering { hovering = inside }
    }

    /// Close button target: persists the setting, which hides the panel.
    func closeRequested() {
        AppState.shared.visualizerEnabled = false
    }

    // MARK: - Drag / resize / reset

    /// Move the panel by a drag delta (SwiftUI coords: +y is down).
    func dragBy(dx: CGFloat, dy: CGFloat) {
        guard let panel else { return }
        var origin = panel.frame.origin
        origin.x += dx
        origin.y -= dy
        panel.setFrameOrigin(origin)
    }

    func dragEnded() {
        guard let panel else { return }
        setCustomOrigin(panel.frame.origin)
    }

    /// Resize from the bottom-right handle, keeping the top-left corner
    /// fixed. `proposedWidth` comes from the gesture; aspect is locked.
    func resizeTo(proposedWidth: CGFloat) {
        guard let panel else { return }
        let newScale = max(1, min(Self.maxScale,
                                  proposedWidth / Self.baseSize.width))
        guard abs(newScale - scale) > 0.001 else { return }
        let frame = panel.frame
        let topLeft = NSPoint(x: frame.minX, y: frame.maxY)
        scale = newScale
        let newSize = size
        panel.setFrame(NSRect(x: topLeft.x,
                              y: topLeft.y - newSize.height,
                              width: newSize.width,
                              height: newSize.height),
                       display: true)
    }

    func resizeEnded() {
        resizing = false
        UserDefaults.standard.set(Double(scale), forKey: "visualizerScale")
        guard let panel else { return }
        setCustomOrigin(panel.frame.origin)
    }

    /// Restore the default size and the preset position.
    func resetLayout() {
        scale = 1
        UserDefaults.standard.set(1.0, forKey: "visualizerScale")
        clearCustomOrigin()
        if let panel {
            panel.setContentSize(size)
            reposition()
        }
    }

    private func setCustomOrigin(_ origin: NSPoint) {
        customOrigin = origin
        let d = UserDefaults.standard
        d.set(true, forKey: "visualizerHasCustomOrigin")
        d.set(Double(origin.x), forKey: "visualizerOriginX")
        d.set(Double(origin.y), forKey: "visualizerOriginY")
    }

    private func clearCustomOrigin() {
        customOrigin = nil
        UserDefaults.standard.set(false, forKey: "visualizerHasCustomOrigin")
    }

    private func reposition() {
        guard let panel else { return }

        // A dragged-to position wins over presets; Follow Cursor recomputes.
        if position != .followCursor, let customOrigin {
            panel.setFrameOrigin(customOrigin)
            return
        }

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
/// Hover reveals a close button (top right) and a resize handle (bottom
/// right); dragging anywhere else moves the panel.
struct MiniKeyboardView: View {
    @EnvironmentObject var controller: VisualizerController

    @State private var lastDrag: CGSize = .zero
    @State private var resizeStartWidth: CGFloat?

    var body: some View {
        GeometryReader { geo in
            KeyboardShapeView(pressedKeys: controller.pressedKeys,
                              keySpacing: 2.5,
                              cornerRadius: 3,
                              showLabels: controller.showLabels)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(red: 0.043, green: 0.051, blue: 0.067)
                            .opacity(0.92))
                )
                .gesture(moveGesture)
                .overlay(alignment: .topTrailing) {
                    if controller.hovering {
                        Button {
                            controller.closeRequested()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white.opacity(0.85))
                                .frame(width: 16, height: 16)
                                .background(.white.opacity(0.18), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(5)
                        .help("Hide visualizer")
                        .transition(.opacity)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if controller.hovering {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 16, height: 16)
                            .background(.white.opacity(0.18), in: Circle())
                            .padding(5)
                            .gesture(resizeGesture(panelWidth: geo.size.width))
                            .help("Drag to resize")
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.12), value: controller.hovering)
                .padding(4)
        }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                controller.dragBy(dx: value.translation.width - lastDrag.width,
                                  dy: value.translation.height - lastDrag.height)
                lastDrag = value.translation
            }
            .onEnded { _ in
                lastDrag = .zero
                controller.dragEnded()
            }
    }

    private func resizeGesture(panelWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                controller.resizing = true
                let start = resizeStartWidth ?? panelWidth
                resizeStartWidth = start
                controller.resizeTo(
                    proposedWidth: start + value.translation.width)
            }
            .onEnded { _ in
                resizeStartWidth = nil
                controller.resizeEnded()
            }
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
