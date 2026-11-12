import AppKit
import ApplicationServices

/// Linux-style window handling: hold Ctrl+Cmd anywhere over a window, then
/// drag to move it or right-drag to resize it from the nearest corner.
/// Needs Accessibility permission.
final class WindowDragger {
    static let shared = WindowDragger()

    private static let enabledKey = "windowDragEnabled"
    private let modifiers: CGEventFlags = [.maskControl, .maskCommand]
    private let relevantModifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift, .maskSecondaryFn]

    private enum Mode { case move, resize }
    private struct Drag {
        let window: AXUIElement
        let mode: Mode
        let startMouse: CGPoint
        let startOrigin: CGPoint
        let startSize: CGSize
        let fromLeft: Bool
        let fromTop: Bool
    }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var drag: Drag?
    private var permissionTimer: Timer?

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            newValue ? start(prompt: true) : stop()
        }
    }

    /// True once the event tap is running.
    var isActive: Bool { tap != nil }

    func startIfEnabled() {
        if isEnabled { start(prompt: true) }
    }

    private func start(prompt: Bool) {
        guard tap == nil else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            // Start as soon as the user grants access in System Settings.
            permissionTimer?.invalidate()
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
                guard let self, self.isEnabled else { timer.invalidate(); return }
                if AXIsProcessTrusted() { timer.invalidate(); self.start(prompt: false) }
            }
            return
        }
        permissionTimer?.invalidate()

        let types: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp,
                                    .rightMouseDown, .rightMouseDragged, .rightMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, _ in
                WindowDragger.shared.handle(type, event) ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: nil
        ) else {
            NSLog("Applight: could not create window-drag event tap")
            return
        }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stop() {
        permissionTimer?.invalidate()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        drag = nil
    }

    /// Returns true when the event should be swallowed.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let location = event.location
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false

        case .leftMouseDown, .rightMouseDown:
            guard event.flags.intersection(relevantModifiers) == modifiers,
                  let window = Self.window(at: location),
                  let origin = Self.point(of: window), let size = Self.size(of: window) else { return false }
            drag = Drag(window: window, mode: type == .leftMouseDown ? .move : .resize,
                        startMouse: location, startOrigin: origin, startSize: size,
                        fromLeft: location.x < origin.x + size.width / 2,
                        fromTop: location.y < origin.y + size.height / 2)
            Self.raise(window)
            return true

        case .leftMouseDragged, .rightMouseDragged:
            guard let drag else { return false }
            let dx = location.x - drag.startMouse.x
            let dy = location.y - drag.startMouse.y
            switch drag.mode {
            case .move:
                Self.setPoint(of: drag.window, CGPoint(x: drag.startOrigin.x + dx, y: drag.startOrigin.y + dy))
            case .resize:
                let width = max(120, drag.startSize.width + (drag.fromLeft ? -dx : dx))
                let height = max(80, drag.startSize.height + (drag.fromTop ? -dy : dy))
                if drag.fromLeft || drag.fromTop {
                    let x = drag.fromLeft ? drag.startOrigin.x + drag.startSize.width - width : drag.startOrigin.x
                    let y = drag.fromTop ? drag.startOrigin.y + drag.startSize.height - height : drag.startOrigin.y
                    Self.setPoint(of: drag.window, CGPoint(x: x, y: y))
                }
                Self.setSize(of: drag.window, CGSize(width: width, height: height))
            }
            return true

        case .leftMouseUp, .rightMouseUp:
            guard drag != nil else { return false }
            drag = nil
            return true

        default:
            return false
        }
    }

    // MARK: - Accessibility helpers

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func window(at point: CGPoint) -> AXUIElement? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success,
              var element = hit else { return nil }
        for _ in 0..<64 {
            if attribute(element, kAXRoleAttribute) as? String == kAXWindowRole { return element }
            if let window = attribute(element, kAXWindowAttribute) { return (window as! AXUIElement) }
            guard let parent = attribute(element, kAXParentAttribute) else { return nil }
            element = parent as! AXUIElement
        }
        return nil
    }

    private static func point(of window: AXUIElement) -> CGPoint? {
        guard let value = attribute(window, kAXPositionAttribute) else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    private static func size(of window: AXUIElement) -> CGSize? {
        guard let value = attribute(window, kAXSizeAttribute) else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }

    private static func setPoint(of window: AXUIElement, _ point: CGPoint) {
        var point = point
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &point)!)
    }

    private static func setSize(of window: AXUIElement, _ size: CGSize) {
        var size = size
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
    }

    private static func raise(_ window: AXUIElement) {
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        NSRunningApplication(processIdentifier: pid)?.activate()
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }
}
