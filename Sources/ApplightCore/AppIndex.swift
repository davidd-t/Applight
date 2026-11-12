import Foundation
import CoreServices

/// The in-memory list of installed apps. Scans the app folders directly
/// (no Spotlight index) and rescans when any of them change.
public final class AppIndex {
    public private(set) var entries: [AppEntry] = []
    /// Called on the main queue after every (re)scan.
    public var onChange: (() -> Void)?

    private var stream: FSEventStreamRef?
    private let scanQueue = DispatchQueue(label: "applight.scan", qos: .userInitiated)

    public static var roots: [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications"),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
    }

    public static let extras = [URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")]

    public init() {}

    /// Synchronous scan; safe to call from any thread.
    public static func scan(roots: [URL] = roots, extras: [URL] = extras) -> [AppEntry] {
        var seen = Set<String>()
        var out: [AppEntry] = []
        func add(_ url: URL, name: String?) {
            let real = url.resolvingSymlinksInPath().path
            guard seen.insert(real).inserted else { return }
            var n = name ?? url.lastPathComponent
            if n.hasSuffix(".app") { n.removeLast(4) }
            // The same system app can appear under two roots (e.g. Safari).
            guard seen.insert("name:" + n + "|" + url.lastPathComponent).inserted else { return }
            out.append(AppEntry(url: url, name: n))
        }
        func walk(_ dir: URL, depth: Int) {
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey, .localizedNameKey],
                options: [.skipsHiddenFiles]
            ) else { return }
            for item in items {
                let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .localizedNameKey])
                if item.pathExtension == "app" {
                    add(item, name: values?.localizedName)
                    // Apps can ship other apps (Xcode → Device Hub, Instruments, FileMerge).
                    walkBundled(item.appendingPathComponent("Contents/Applications"))
                } else if depth < 2, values?.isDirectory == true {
                    walk(item, depth: depth + 1)
                }
            }
        }
        func walkBundled(_ dir: URL) {
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.localizedNameKey], options: [.skipsHiddenFiles]
            ) else { return }
            for item in items where item.pathExtension == "app" {
                add(item, name: try? item.resourceValues(forKeys: [.localizedNameKey]).localizedName)
            }
        }
        for root in roots { walk(root, depth: 0) }
        for extra in extras where FileManager.default.fileExists(atPath: extra.path) {
            let name = try? extra.resourceValues(forKeys: [.localizedNameKey]).localizedName
            add(extra, name: name)
        }
        return out
    }

    /// Scans in the background and starts watching the app folders.
    public func start() {
        rescan()
        watch()
    }

    private func rescan() {
        scanQueue.async { [weak self] in
            let fresh = AppIndex.scan()
            DispatchQueue.main.async {
                self?.entries = fresh
                self?.onChange?()
            }
        }
    }

    private func watch() {
        let paths = AppIndex.roots.map(\.path) as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<AppIndex>.fromOpaque(info).takeUnretainedValue().rescan()
        }
        guard let s = FSEventStreamCreate(
            nil, callback, &context, paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)
        ) else { return }
        FSEventStreamSetDispatchQueue(s, .main)
        FSEventStreamStart(s)
        stream = s
    }
}
