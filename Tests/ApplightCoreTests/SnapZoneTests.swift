import XCTest
@testable import ApplightCore

final class SnapZoneTests: XCTestCase {
    // A 1000×800 screen placed right of a primary display, to catch origin mistakes.
    let screen = CGRect(x: 1000, y: 0, width: 1000, height: 800)

    private func zone(_ x: CGFloat, _ y: CGFloat) -> SnapZone? {
        SnapZone.zone(at: CGPoint(x: x, y: y), screen: screen)
    }

    func testMiddleOfScreenIsNoZone() {
        XCTAssertNil(zone(1500, 400))
    }

    func testEdges() {
        XCTAssertEqual(zone(1000, 400), .left)
        XCTAssertEqual(zone(1999, 400), .right)
        XCTAssertEqual(zone(1500, 0), .maximize)
    }

    func testBottomEdgeMiddleDoesNothing() {
        // The Dock lives there; only its corners snap.
        XCTAssertNil(zone(1500, 799))
    }

    func testCornersFromEitherEdge() {
        XCTAssertEqual(zone(1000, 50), .topLeft)      // left edge, near top
        XCTAssertEqual(zone(1050, 0), .topLeft)       // top edge, near left
        XCTAssertEqual(zone(1999, 50), .topRight)
        XCTAssertEqual(zone(1950, 0), .topRight)
        XCTAssertEqual(zone(1000, 750), .bottomLeft)
        XCTAssertEqual(zone(1050, 799), .bottomLeft)
        XCTAssertEqual(zone(1999, 750), .bottomRight)
        XCTAssertEqual(zone(1950, 799), .bottomRight)
    }

    func testFramesTileTheVisibleArea() {
        let visible = CGRect(x: 1000, y: 25, width: 1001, height: 701)   // odd sizes: no gaps, no overlap
        XCTAssertEqual(SnapZone.maximize.frame(in: visible), visible)
        let left = SnapZone.left.frame(in: visible), right = SnapZone.right.frame(in: visible)
        XCTAssertEqual(left.maxX, right.minX)
        XCTAssertEqual(left.width + right.width, visible.width)
        let tl = SnapZone.topLeft.frame(in: visible), br = SnapZone.bottomRight.frame(in: visible)
        XCTAssertEqual(tl.origin, visible.origin)
        XCTAssertEqual(tl.maxX, br.minX)
        XCTAssertEqual(tl.maxY, br.minY)
        XCTAssertEqual(br.maxX, visible.maxX)
        XCTAssertEqual(br.maxY, visible.maxY)
    }
}
