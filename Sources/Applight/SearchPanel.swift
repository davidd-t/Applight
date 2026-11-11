import AppKit
import ApplightCore

final class SearchPanel: NSPanel {
    var onCommandReturn: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, event.keyCode == 36, event.modifierFlags.contains(.command) {
            onCommandReturn?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

private final class FlippedView: NSView {
    var onResize: (() -> Void)?
    override var isFlipped: Bool { true }
    override func resizeSubviews(withOldSize oldSize: NSSize) { onResize?() }
}

private final class RowView: NSTableRowView {
    override var isEmphasized: Bool { get { false } set {} }
    override func drawSelection(in dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: Metrics.listInset, dy: 1)
        Metrics.highlightColor.setFill()
        NSBezierPath(roundedRect: r, xRadius: Metrics.highlightRadius, yRadius: Metrics.highlightRadius).fill()
    }
    override func drawBackground(in dirtyRect: NSRect) {}
}

private final class CellView: NSView {
    let icon = NSImageView()
    let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        icon.imageScaling = .scaleProportionallyUpOrDown
        label.font = Metrics.rowFont
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        addSubview(icon)
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let h = bounds.height
        // The table insets cells slightly; measure from the row's own edge instead.
        let x0 = Metrics.listInset - frame.minX
        icon.frame = NSRect(x: x0 + Metrics.rowIconLeading, y: (h - Metrics.rowIconSize) / 2,
                            width: Metrics.rowIconSize, height: Metrics.rowIconSize)
        let lh = ceil(label.intrinsicContentSize.height)
        let lx = x0 + Metrics.rowTextLeading
        label.frame = NSRect(x: lx, y: (h - lh) / 2, width: bounds.width - lx - 24, height: lh)
    }
}

/// Owns the Spotlight-style window: a glass bar that grows a result list as you type.
final class SearchController: NSObject, NSWindowDelegate, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let index: AppIndex
    private let usage: Usage
    private let panel: SearchPanel
    private let content = FlippedView()
    private let glassIcon = NSImageView()
    private let field = NSTextField()
    private let completion = NSTextField(labelWithString: "")
    private let hintBackground = NSView()
    private let barAppIcon = NSImageView()
    private let scroll = NSScrollView()
    private let table = NSTableView()
    private var results: [AppEntry] = []
    private var icons: [String: NSImage] = [:]
    private let glass = NSGlassEffectView()

    /// The window never changes size: it is a transparent canvas big enough for the tallest
    /// list plus a margin, and only the glass inside it grows. That keeps the glass's own
    /// shadow from being clipped into a hard rectangle and avoids resizing a window per keystroke.
    private static let margin: CGFloat = 60
    private static var maxGlassHeight: CGFloat {
        Metrics.barHeight + CGFloat(Metrics.maxVisibleRows) * Metrics.rowHeight + Metrics.listBottomPadding
    }
    private static var windowSize: NSSize {
        NSSize(width: Metrics.width + margin * 2, height: maxGlassHeight + margin * 2)
    }

    var isVisible: Bool { panel.isVisible }

    init(index: AppIndex, usage: Usage) {
        self.index = index
        self.usage = usage
        panel = SearchPanel(
            contentRect: NSRect(origin: .zero, size: SearchController.windowSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        super.init()
        buildWindow()
    }

    // MARK: Construction

    private func buildWindow() {
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.onCommandReturn = { [weak self] in self?.revealSelection() }

        let root = NSView(frame: NSRect(origin: .zero, size: Self.windowSize))
        panel.contentView = root
        glass.frame = glassFrame(height: Metrics.barHeight)
        glass.cornerRadius = Metrics.cornerRadius
        content.frame = glass.bounds
        content.autoresizingMask = [.width, .height]
        content.onResize = { [weak self] in self?.layoutContent() }
        glass.contentView = content
        root.addSubview(glass)

        let symbol = NSImage.SymbolConfiguration(pointSize: Metrics.iconPointSize, weight: .medium)
        glassIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search")?
            .withSymbolConfiguration(symbol)
        glassIcon.contentTintColor = .secondaryLabelColor
        content.addSubview(glassIcon)

        hintBackground.wantsLayer = true
        hintBackground.layer?.cornerRadius = Metrics.hintRadius
        hintBackground.layer?.cornerCurve = .continuous
        content.addSubview(hintBackground)

        completion.font = Metrics.font
        completion.textColor = .secondaryLabelColor
        completion.lineBreakMode = .byTruncatingTail
        content.addSubview(completion)

        barAppIcon.imageScaling = .scaleProportionallyUpOrDown
        content.addSubview(barAppIcon)

        field.font = Metrics.font
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = .labelColor
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.placeholderAttributedString = NSAttributedString(
            string: Metrics.placeholder,
            attributes: [.font: Metrics.font, .foregroundColor: NSColor.secondaryLabelColor]
        )
        field.delegate = self
        content.addSubview(field)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .fullWidth
        table.backgroundColor = .clear
        table.rowHeight = Metrics.rowHeight
        table.intercellSpacing = .zero
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.allowsEmptySelection = true
        table.refusesFirstResponder = true
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)

        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false
        content.addSubview(scroll)

        layoutContent()
    }

    private func layoutContent() {
        let w = content.bounds.width
        let bar = Metrics.barHeight
        let dy = Metrics.barYOffset
        glassIcon.frame = NSRect(x: Metrics.iconLeading, y: (bar - Metrics.iconSize) / 2 + dy,
                                 width: Metrics.iconSize, height: Metrics.iconSize)
        let fh = ceil(field.intrinsicContentSize.height)
        barAppIcon.frame = NSRect(x: w - Metrics.barAppIconTrailing - Metrics.barAppIconSize,
                                  y: (bar - Metrics.barAppIconSize) / 2 + dy,
                                  width: Metrics.barAppIconSize, height: Metrics.barAppIconSize)
        field.frame = NSRect(x: Metrics.fieldLeading, y: (bar - fh) / 2 + dy,
                             width: w - Metrics.fieldLeading - Metrics.fieldTrailing, height: fh)
        scroll.frame = NSRect(x: 0, y: bar, width: w,
                              height: max(0, content.bounds.height - bar - Metrics.listBottomPadding))
        layoutCompletion()
    }

    // MARK: Show / hide

    func toggle() { isVisible ? hide() : show() }

    func show() {
        field.stringValue = ""
        refresh(animated: false)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let f = screen.frame
        let top = f.maxY - f.height * Metrics.topFraction  // top edge of the bar
        let size = Self.windowSize
        panel.setFrame(NSRect(x: f.midX - size.width / 2, y: top + Self.margin - size.height,
                              width: size.width, height: size.height), display: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) { hide() }

    /// Called when the app list changes while the panel is open.
    func indexDidChange() {
        prewarmIcons()
        if isVisible { refresh(animated: true) }
    }

    // MARK: Searching

    func controlTextDidChange(_ obj: Notification) { refresh(animated: true) }

    private func refresh(animated: Bool) {
        results = SearchEngine.search(field.stringValue, in: index.entries, usage: usage)
        table.reloadData()
        if !results.isEmpty {
            table.selectRowIndexes([0], byExtendingSelection: false)
            table.scrollRowToVisible(0)
        }
        layoutCompletion()
        resize(animated: animated)
    }

    private func glassFrame(height: CGFloat) -> NSRect {
        NSRect(x: Self.margin, y: Self.windowSize.height - Self.margin - height,
               width: Metrics.width, height: height)
    }

    private func resize(animated: Bool) {
        let rows = min(results.count, Metrics.maxVisibleRows)
        let height = Metrics.barHeight + (rows > 0 ? CGFloat(rows) * Metrics.rowHeight + Metrics.listBottomPadding : 0)
        guard glass.frame.height != height else { return }
        glass.frame = glassFrame(height: height)
        content.frame = glass.bounds
        layoutContent()
    }

    /// Spotlight-style inline hint after the typed text: the rest of the top hit's name.
    private func layoutCompletion() {
        let typed = field.stringValue
        guard let top = selected ?? results.first, !typed.isEmpty,
              (field.currentEditor() as? NSTextView)?.hasMarkedText() != true else {
            completion.isHidden = true
            hintBackground.isHidden = true
            barAppIcon.image = nil
            return
        }
        barAppIcon.image = icon(for: top)
        let hint: String
        if top.name.lowercased().hasPrefix(typed.lowercased()) {
            hint = String(top.name.dropFirst(typed.count)) + " — Open"
        } else {
            hint = " — " + top.name
        }
        let typedWidth = ceil((typed as NSString).size(withAttributes: [.font: Metrics.font]).width)
        let x = field.frame.minX + 2 + typedWidth
        let available = field.frame.maxX - x
        guard available > 40 else {
            completion.isHidden = true
            hintBackground.isHidden = true
            return
        }
        completion.stringValue = hint
        let hintWidth = min(available, ceil((hint as NSString).size(withAttributes: [.font: Metrics.font]).width) + 4)
        completion.frame = NSRect(x: x, y: field.frame.minY, width: hintWidth, height: field.frame.height)
        completion.isHidden = false
        hintBackground.layer?.backgroundColor = Metrics.hintBackground.cgColor
        hintBackground.frame = NSRect(x: x + 1, y: field.frame.minY, width: hintWidth + 3, height: field.frame.height)
        hintBackground.isHidden = false
    }

    // MARK: Keyboard

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)): move(1); return true
        case #selector(NSResponder.moveUp(_:)): move(-1); return true
        case #selector(NSResponder.insertNewline(_:)): launchSelection(); return true
        case #selector(NSResponder.cancelOperation(_:)): hide(); return true
        case #selector(NSResponder.insertTab(_:)): move(1); return true
        case #selector(NSResponder.insertBacktab(_:)): move(-1); return true
        default: return false
        }
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        let row = max(0, min(results.count - 1, table.selectedRow + delta))
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
        layoutCompletion()
    }

    private var selected: AppEntry? {
        let row = table.selectedRow
        return row >= 0 && row < results.count ? results[row] : nil
    }

    @objc private func rowClicked() {
        guard table.clickedRow >= 0 else { return }
        table.selectRowIndexes([table.clickedRow], byExtendingSelection: false)
        launchSelection()
    }

    private func launchSelection() {
        guard let app = selected else { return }
        usage.record(path: app.path, query: SearchEngine.usageKey(field.stringValue))
        hide()
        NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func revealSelection() {
        guard let app = selected else { return }
        hide()
        NSWorkspace.shared.activateFileViewerSelecting([app.url])
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let id = NSUserInterfaceItemIdentifier("row")
        if let reused = tableView.makeView(withIdentifier: id, owner: nil) as? RowView { return reused }
        let view = RowView()
        view.identifier = id
        return view
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? CellView ?? {
            let c = CellView(frame: .zero)
            c.identifier = id
            return c
        }()
        let app = results[row]
        cell.label.stringValue = app.name
        cell.icon.image = icon(for: app)
        cell.needsLayout = true
        return cell
    }

    private func icon(for app: AppEntry) -> NSImage {
        icons[app.path] ?? NSWorkspace.shared.icon(forFile: app.path)
    }

    /// The system loads app icons lazily, so the first draw can come up blank.
    /// Draw every icon once up front, then keep finished bitmaps so rows appear complete.
    func prewarmIcons() {
        let pending = index.entries.filter { icons[$0.path] == nil }
        guard !pending.isEmpty else { return }
        let live = pending.map { ($0.path, NSWorkspace.shared.icon(forFile: $0.path)) }
        for (path, image) in live { icons[path] = Self.rasterize(image) }
        for delay in [3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                for (path, image) in live { self.icons[path] = Self.rasterize(image) }
                if self.isVisible {
                    let row = self.table.selectedRow
                    self.table.reloadData()
                    if row >= 0 { self.table.selectRowIndexes([row], byExtendingSelection: false) }
                }
            }
        }
    }

    private static func rasterize(_ image: NSImage) -> NSImage {
        let points = Metrics.rowIconSize
        let pixels = Int(points * 2)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ), let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return image }
        // Draw at 1x into the full pixel grid, then label the bitmap as 2x.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        rep.size = NSSize(width: points, height: points)
        let out = NSImage(size: rep.size)
        out.addRepresentation(rep)
        return out
    }

    // MARK: Debug

    /// Renders the panel's layout (without the live glass) to a PNG, for checking geometry.
    func snapshot(query: String, to path: String) {
        let view: NSView = glass
        show()
        field.stringValue = query
        refresh(animated: false)
        panel.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
