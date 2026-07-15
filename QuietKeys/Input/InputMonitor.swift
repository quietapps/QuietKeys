import AppKit
import CoreGraphics

/// System-wide keyboard + mouse listener built on a listen-only CGEvent tap.
/// Requires the Accessibility (Input Monitoring) permission; the tap never
/// modifies or consumes events.
final class InputMonitor {
    struct KeyEvent {
        let keyCode: Int64
        let isDown: Bool
        let isRepeat: Bool
    }

    enum MouseEvent {
        case left(down: Bool)
        case right(down: Bool)
        case middle(down: Bool)
    }

    /// Called on the tap thread — handlers must be fast and thread-safe.
    var onKey: ((KeyEvent) -> Void)?
    var onMouse: ((MouseEvent) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var thread: Thread?

    private(set) var isRunning = false

    static var hasPermission: Bool {
        AXIsProcessTrusted()
    }

    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func start() {
        guard !isRunning, Self.hasPermission else { return }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<InputMonitor>.fromOpaque(userInfo)
                    .takeUnretainedValue()
                monitor.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr)
        else { return }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source

        // Dedicated thread keeps latency independent of main-thread load.
        let thread = Thread { [weak self] in
            guard let self, let source = self.runLoopSource else { return }
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            while self.isRunning {
                CFRunLoopRunInMode(.defaultMode, 0.25, false)
            }
        }
        thread.name = "QuietKeys.InputMonitor"
        thread.qualityOfService = .userInteractive
        isRunning = true
        thread.start()
        self.thread = thread
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        tap = nil
        runLoopSource = nil
        thread = nil
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .keyDown, .keyUp:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            onKey?(KeyEvent(keyCode: keyCode,
                            isDown: type == .keyDown,
                            isRepeat: isRepeat))
        case .leftMouseDown: onMouse?(.left(down: true))
        case .leftMouseUp: onMouse?(.left(down: false))
        case .rightMouseDown: onMouse?(.right(down: true))
        case .rightMouseUp: onMouse?(.right(down: false))
        case .otherMouseDown: onMouse?(.middle(down: true))
        case .otherMouseUp: onMouse?(.middle(down: false))
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        default:
            break
        }
    }
}
