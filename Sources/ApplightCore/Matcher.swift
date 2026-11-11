import Foundation

/// An installed application, with its name pre-processed for matching.
public struct AppEntry {
    public let url: URL
    public let name: String
    /// Lowercased, diacritic-free scalars of `name`.
    let folded: [Unicode.Scalar]
    /// `boundary[i]` is true when `folded[i]` starts a word ("Visual Studio", "QuickTime").
    let boundary: [Bool]
    /// The scalars at word starts: "vsc" for Visual Studio Code.
    let initials: [Unicode.Scalar]

    public var path: String { url.path }

    public init(url: URL, name: String) {
        self.url = url
        self.name = name
        let scalars = Array(name.folding(options: .diacriticInsensitive, locale: nil).unicodeScalars)
        var folded: [Unicode.Scalar] = []
        var boundary: [Bool] = []
        var initials: [Unicode.Scalar] = []
        folded.reserveCapacity(scalars.count)
        boundary.reserveCapacity(scalars.count)
        for (i, s) in scalars.enumerated() {
            let props = s.properties
            let alnum = props.isAlphabetic || props.numericType != nil
            let lower = Matcher.lower(s)
            var start = false
            if alnum {
                if i == 0 {
                    start = true
                } else {
                    let p = scalars[i - 1].properties
                    let prevAlnum = p.isAlphabetic || p.numericType != nil
                    start = !prevAlnum
                        || (p.isLowercase && props.isUppercase)
                        || (p.isAlphabetic && props.numericType != nil)
                }
            }
            folded.append(lower)
            boundary.append(start)
            if start { initials.append(lower) }
        }
        self.folded = folded
        self.boundary = boundary
        self.initials = initials
    }
}

public enum Matcher {
    static func lower(_ s: Unicode.Scalar) -> Unicode.Scalar {
        if s.isASCII {
            return (s.value >= 65 && s.value <= 90) ? Unicode.Scalar(s.value + 32)! : s
        }
        return String(s).lowercased().unicodeScalars.first ?? s
    }

    /// Prepares a typed query for `score`. Whitespace is ignored so "vs code" works.
    public static func fold(_ query: String) -> [Unicode.Scalar] {
        query.folding(options: .diacriticInsensitive, locale: nil)
            .unicodeScalars
            .filter { !$0.properties.isWhitespace }
            .map(lower)
    }

    /// Returns nil when the query doesn't match; higher is better.
    /// Tiers: name prefix > word prefix > initials > substring > scattered letters.
    public static func score(_ q: [Unicode.Scalar], _ e: AppEntry) -> Int? {
        let n = e.folded
        guard !q.isEmpty, q.count <= n.count else { return nil }

        if hasPrefix(n, q, at: 0) {
            return 10_000 - n.count + (n.count == q.count ? 500 : 0)
        }
        var i = 1
        while i <= n.count - q.count {
            if e.boundary[i], hasPrefix(n, q, at: i) { return 8_000 - i - n.count }
            i += 1
        }
        if q.count >= 2, q.count <= e.initials.count, hasPrefix(e.initials, q, at: 0) {
            return 7_000 - n.count
        }
        // Spaces are stripped from the query, so also compare against the name without separators.
        i = 1
        while i <= n.count - q.count {
            if hasPrefix(n, q, at: i) { return 5_000 - i - n.count }
            i += 1
        }
        guard let s = subsequence(q, e) else { return nil }
        return 1_000 + s - n.count
    }

    @inline(__always)
    private static func hasPrefix(_ n: [Unicode.Scalar], _ q: [Unicode.Scalar], at start: Int) -> Bool {
        if start + q.count > n.count { return false }
        var k = 0
        while k < q.count {
            if n[start + k] != q[k] { return false }
            k += 1
        }
        return true
    }

    /// Best score for matching q's letters in order anywhere in the name,
    /// rewarding word starts and runs of consecutive letters.
    private static func subsequence(_ q: [Unicode.Scalar], _ e: AppEntry) -> Int? {
        let n = e.folded
        let minScore = Int.min / 2
        // prev[j]: best score with the previous query letter matched exactly at j.
        var prev = [Int](repeating: minScore, count: n.count)
        var cur = [Int](repeating: minScore, count: n.count)
        for (qi, ch) in q.enumerated() {
            var bestBefore = minScore  // best of prev[0..<j-1], minus gap cost
            var any = false
            for j in 0..<n.count {
                if j >= 2, prev[j - 2] > minScore {
                    bestBefore = max(bestBefore, prev[j - 2])
                }
                if bestBefore > minScore { bestBefore -= 2 }
                cur[j] = minScore
                guard n[j] == ch else { continue }
                let bonus = e.boundary[j] ? 60 : 0
                if qi == 0 {
                    cur[j] = bonus - j * 2
                    any = true
                } else {
                    var best = bestBefore
                    if j >= 1, prev[j - 1] > minScore { best = max(best, prev[j - 1] + 40) }
                    if best > minScore {
                        cur[j] = best + bonus
                        any = true
                    }
                }
            }
            if !any { return nil }
            swap(&prev, &cur)
        }
        let best = prev.max() ?? minScore
        return best > minScore ? best : nil
    }
}
