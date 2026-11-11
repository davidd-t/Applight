import AppKit

/// Every measurement of the Spotlight look lives here, so it can be tuned
/// against the real thing without touching layout code.
enum Metrics {
    // Panel
    static let width: CGFloat = 640
    static let barHeight: CGFloat = 56
    static let cornerRadius: CGFloat = 28
    /// Distance from the top of the screen to the top of the bar, as a fraction of screen height.
    static let topFraction: CGFloat = 0.255

    // Search bar
    static let iconLeading: CGFloat = 19
    static let iconSize: CGFloat = 28
    static let iconPointSize: CGFloat = 23
    static let fieldLeading: CGFloat = 59
    static let fieldTrailing: CGFloat = 60
    static let font = NSFont.systemFont(ofSize: 26, weight: .regular)
    static let placeholder = "Applight Search"
    /// Vertical nudge of the bar's icon and text (negative is up).
    static let barYOffset: CGFloat = -1.5
    /// The top hit's icon at the right end of the bar.
    static let barAppIconSize: CGFloat = 33
    static let barAppIconTrailing: CGFloat = 19
    static let hintBackground = NSColor.labelColor.withAlphaComponent(0.14)
    static let hintRadius: CGFloat = 6

    // Results
    static let rowHeight: CGFloat = 56
    static let maxVisibleRows = 7
    static let listInset: CGFloat = 10         // highlight inset from panel edge
    static let listBottomPadding: CGFloat = 10
    static let rowIconSize: CGFloat = 44
    static let rowIconLeading: CGFloat = 2.5    // from highlight edge
    static let rowTextLeading: CGFloat = 61
    static let rowFont = NSFont.systemFont(ofSize: 16, weight: .medium)
    static let highlightRadius: CGFloat = 16
    static let highlightColor = NSColor.labelColor.withAlphaComponent(0.2)
}
