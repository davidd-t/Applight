import AppKit
import ApplightCore

/// Screen geometry in the global top-left-origin space used by CGEvent and Accessibility.
enum ScreenSpace {
    private static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    /// Flips a rect between AppKit (bottom-left origin) and global top-left coordinates. Works both ways.
    static func flip(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    /// The screen under a top-left-origin point: its full frame and its visible frame (no menu bar or Dock).
    static func screen(at point: CGPoint) -> (frame: CGRect, visible: CGRect)? {
        for screen in NSScreen.screens {
            let frame = flip(screen.frame)
            if point.x >= frame.minX, point.x < frame.maxX, point.y >= frame.minY, point.y < frame.maxY {
                return (frame, flip(screen.visibleFrame))
            }
        }
        return nil
    }
}

/// The translucent rectangle that shows where a dragged window will snap.
final class SnapPreview {
    private var panel: NSPanel?
    private(set) var shownFrame: CGRect?

    /// Shows the preview at `frame` (top-left-origin coordinates), animating from its last position.
    func show(_ frame: CGRect) {
        guard frame != shownFrame else { return }
        let panel = self.panel ?? makePanel()
        let target = ScreenSpace.flip(frame).insetBy(dx: 6, dy: 6)
        if shownFrame == nil {
            // Grow out of a smaller rect in the middle of the target.
            panel.setFrame(target.insetBy(dx: target.width * 0.1, dy: target.height * 0.1), display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        shownFrame = frame
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel, shownFrame != nil else { return }
        shownFrame = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            if self?.shownFrame == nil { panel.orderOut(nil) }
        })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.isReleasedWhenClosed = false

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 14
        blur.layer?.masksToBounds = true
        blur.layer?.borderWidth = 1
        blur.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor

        let tint = NSView()
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
        tint.autoresizingMask = [.width, .height]
        blur.addSubview(tint)

        panel.contentView = blur
        tint.frame = blur.bounds
        self.panel = panel
        return panel
    }
}
