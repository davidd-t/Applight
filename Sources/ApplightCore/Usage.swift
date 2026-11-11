import Foundation

/// Remembers what you launch, so frequent apps and habitual abbreviations rank first.
public final class Usage {
    private let defaults: UserDefaults
    private var launches: [String: Int]
    /// query -> app path -> times chosen
    private var picks: [String: [String: Int]]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        launches = defaults.dictionary(forKey: "launches") as? [String: Int] ?? [:]
        picks = defaults.dictionary(forKey: "picks") as? [String: [String: Int]] ?? [:]
    }

    public func record(path: String, query: String) {
        launches[path, default: 0] += 1
        if !query.isEmpty { picks[query, default: [:]][path, default: 0] += 1 }
        defaults.set(launches, forKey: "launches")
        defaults.set(picks, forKey: "picks")
    }

    /// Extra score for an app given the typed query.
    public func bonus(path: String, query: String) -> Int {
        var b = min(launches[path] ?? 0, 60) * 15
        if let chosen = picks[query]?[path] { b += 20_000 + min(chosen, 100) * 10 }
        return b
    }
}

public struct SearchEngine {
    public static func search(_ query: String, in entries: [AppEntry], usage: Usage?, limit: Int = 50) -> [AppEntry] {
        let q = Matcher.fold(query)
        guard !q.isEmpty else { return [] }
        let key = String(String.UnicodeScalarView(q))
        var hits: [(score: Int, entry: AppEntry)] = []
        for e in entries {
            guard let s = Matcher.score(q, e) else { continue }
            hits.append((s + (usage?.bonus(path: e.path, query: key) ?? 0), e))
        }
        hits.sort {
            $0.score != $1.score
                ? $0.score > $1.score
                : $0.entry.name.localizedCaseInsensitiveCompare($1.entry.name) == .orderedAscending
        }
        return hits.prefix(limit).map(\.entry)
    }

    /// The key under which a pick for this query is remembered.
    public static func usageKey(_ query: String) -> String {
        String(String.UnicodeScalarView(Matcher.fold(query)))
    }
}
