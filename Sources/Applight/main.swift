import AppKit
import Carbon.HIToolbox
import ServiceManagement
import ApplightCore

// `Applight --query <text>` prints ranked matches and timings, without starting the UI.
let arguments = CommandLine.arguments
if let i = arguments.firstIndex(of: "--query"), i + 1 < arguments.count {
    let clock = ContinuousClock()
    var entries: [AppEntry] = []
    let scanTime = clock.measure { entries = AppIndex.scan() }
    var hits: [AppEntry] = []
    let searchTime = clock.measure { hits = SearchEngine.search(arguments[i + 1], in: entries, usage: nil) }
    print("\(entries.count) apps scanned in \(scanTime), searched in \(searchTime)")
    for hit in hits.prefix(8) { print("  \(hit.name)  —  \(hit.path)") }
    exit(0)
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let index = AppIndex()
    private let usage = Usage()
    private var controller: SearchController!
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem!
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = SearchController(index: index, usage: usage)
        index.onChange = { [weak self] in self?.controller.indexDidChange() }
        index.start()

        buildMainMenu()
        buildStatusItem()

        hotKey = HotKey(keyCode: kVK_Space, modifiers: cmdKey) { [weak self] in self?.controller.toggle() }
        if hotKey == nil {
            NSLog("Applight: could not register Cmd+Space")
        }

        let defaults = UserDefaults.standard
        if Bundle.main.bundlePath.hasSuffix(".app"), !defaults.bool(forKey: "didSetUpLogin") {
            defaults.set(true, forKey: "didSetUpLogin")
            try? SMAppService.mainApp.register()
        }

        if let i = arguments.firstIndex(of: "--snapshot"), i + 2 < arguments.count {
            // Give the background scan a moment, then render and quit.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.controller.snapshot(query: arguments[i + 1], to: arguments[i + 2])
                NSApp.terminate(nil)
            }
        }
    }

    /// Opening the app again (e.g. from Finder) shows the search bar.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller.show()
        return false
    }

    // An Edit menu so Cmd+A/C/V/X/Z work in the search field.
    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        appItem.submenu?.addItem(withTitle: "Quit Applight", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Applight")
        let menu = NSMenu()
        menu.delegate = self
        let show = NSMenuItem(title: "Show Applight", action: #selector(showPanel), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Applight", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func showPanel() {
        // Let the status menu finish closing before taking key focus.
        DispatchQueue.main.async { self.controller.show() }
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSLog("Applight: login item change failed: \(error.localizedDescription)")
        }
    }
}

// Only one copy should own the shortcut.
let bundleID = Bundle.main.bundleIdentifier
if let bundleID, NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1,
   !arguments.contains("--snapshot") {
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
