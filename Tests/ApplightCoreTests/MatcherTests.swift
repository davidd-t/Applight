import XCTest
@testable import ApplightCore

final class MatcherTests: XCTestCase {
    private func apps(_ names: [String]) -> [AppEntry] {
        names.map { AppEntry(url: URL(fileURLWithPath: "/Applications/\($0).app"), name: $0) }
    }

    private func top(_ q: String, _ names: [String]) -> String? {
        SearchEngine.search(q, in: apps(names), usage: nil).first?.name
    }

    func testPrefixBeatsSubstring() {
        XCTAssertEqual(top("saf", ["Disk Safety", "Safari", "Unsafe"]), "Safari")
    }

    func testInitials() {
        XCTAssertEqual(top("vsc", ["Vesuvius Cam Viewer Classic", "Visual Studio Code"]), "Visual Studio Code")
    }

    func testScatteredLetters() {
        XCTAssertEqual(top("ps", ["Adobe Photoshop 2026", "Mail"]), "Adobe Photoshop 2026")
    }

    func testWordPrefix() {
        XCTAssertEqual(top("code", ["Barcode Maker", "Visual Studio Code"]), "Visual Studio Code")
    }

    func testCamelCaseAndSpaces() {
        XCTAssertEqual(top("time", ["Sometimes", "QuickTime Player"]), "QuickTime Player")
        XCTAssertEqual(top("vs code", ["Visual Studio Code"]), "Visual Studio Code")
    }

    func testNoMatchAndEmpty() {
        XCTAssertTrue(SearchEngine.search("zzz", in: apps(["Safari"]), usage: nil).isEmpty)
        XCTAssertTrue(SearchEngine.search("  ", in: apps(["Safari"]), usage: nil).isEmpty)
    }

    func testDiacritics() {
        XCTAssertEqual(top("pokemon", ["Pokémon TCG"]), "Pokémon TCG")
    }

    func testLearnedPickWins() {
        let suite = "applight.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let usage = Usage(defaults: defaults)
        let list = apps(["Safari", "Sandbox"])
        XCTAssertEqual(SearchEngine.search("sa", in: list, usage: usage).first?.name, "Safari")
        usage.record(path: "/Applications/Sandbox.app", query: SearchEngine.usageKey("sa"))
        XCTAssertEqual(SearchEngine.search("sa", in: list, usage: usage).first?.name, "Sandbox")
    }
}
