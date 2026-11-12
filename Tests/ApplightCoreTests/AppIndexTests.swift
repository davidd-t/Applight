import XCTest
@testable import ApplightCore

final class AppIndexTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeApp(_ relativePath: String) throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(relativePath).appendingPathComponent("Contents"),
            withIntermediateDirectories: true)
    }

    private func names() -> Set<String> {
        Set(AppIndex.scan(roots: [root], extras: []).map(\.name))
    }

    func testFindsTopLevelApps() throws {
        try makeApp("Safari.app")
        XCTAssertEqual(names(), ["Safari"])
    }

    // Xcode ships Device Hub, Instruments, FileMerge... inside Xcode.app/Contents/Applications.
    func testFindsAppsBundledInsideAnotherApp() throws {
        try makeApp("Xcode.app/Contents/Applications/Instruments.app")
        try makeApp("Xcode.app/Contents/Applications/FileMerge.app")
        XCTAssertEqual(names(), ["Xcode", "Instruments", "FileMerge"])
    }

    func testDoesNotWanderIntoOtherBundleFolders() throws {
        try makeApp("Tool.app/Contents/Resources/Helper.app")
        try makeApp("Tool.app/Contents/Library/LoginItems/Agent.app")
        XCTAssertEqual(names(), ["Tool"])
    }
}
