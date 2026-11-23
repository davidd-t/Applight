import CoreGraphics

/// Where a dragged window lands when the cursor is pushed against a screen edge.
/// All rects and points use global top-left-origin coordinates (like CGEvent and Accessibility).
public enum SnapZone: Equatable, CaseIterable, Sendable {
    case left, right, maximize
    case topLeft, topRight, bottomLeft, bottomRight

    /// The zone under `point`, or nil when the cursor is not against an edge of `screen`.
    /// - Parameters:
    ///   - screen: the full screen frame (the cursor can reach its edges).
    ///   - edge: how close to an edge counts as touching it.
    ///   - corner: how far along an edge from a corner still counts as the corner.
    public static func zone(at point: CGPoint, screen: CGRect, edge: CGFloat = 6, corner: CGFloat = 120) -> SnapZone? {
        let atLeft = point.x <= screen.minX + edge
        let atRight = point.x >= screen.maxX - 1 - edge
        let atTop = point.y <= screen.minY + edge
        let atBottom = point.y >= screen.maxY - 1 - edge
        let nearTop = point.y <= screen.minY + corner
        let nearBottom = point.y >= screen.maxY - corner
        let nearLeft = point.x <= screen.minX + corner
        let nearRight = point.x >= screen.maxX - corner

        if atLeft { return nearTop ? .topLeft : nearBottom ? .bottomLeft : .left }
        if atRight { return nearTop ? .topRight : nearBottom ? .bottomRight : .right }
        if atTop { return nearLeft ? .topLeft : nearRight ? .topRight : .maximize }
        if atBottom { return nearLeft ? .bottomLeft : nearRight ? .bottomRight : nil }
        return nil
    }

    /// The frame a window takes in this zone, inside `visible` (the screen minus menu bar and Dock).
    public func frame(in visible: CGRect) -> CGRect {
        let v = visible
        let halfW = (v.width / 2).rounded()
        let halfH = (v.height / 2).rounded()
        switch self {
        case .maximize: return v
        case .left: return CGRect(x: v.minX, y: v.minY, width: halfW, height: v.height)
        case .right: return CGRect(x: v.minX + halfW, y: v.minY, width: v.width - halfW, height: v.height)
        case .topLeft: return CGRect(x: v.minX, y: v.minY, width: halfW, height: halfH)
        case .topRight: return CGRect(x: v.minX + halfW, y: v.minY, width: v.width - halfW, height: halfH)
        case .bottomLeft: return CGRect(x: v.minX, y: v.minY + halfH, width: halfW, height: v.height - halfH)
        case .bottomRight: return CGRect(x: v.minX + halfW, y: v.minY + halfH, width: v.width - halfW, height: v.height - halfH)
        }
    }
}
