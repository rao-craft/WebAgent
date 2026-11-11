import Foundation

/// The engines' results as one list: reciprocal-rank fusion, so a page several engines rank well comes first.
public enum Fusion {
    public struct Fused: Sendable, Equatable {
        public var url: URL
        public var title: String
        public var snippet: String
        /// The engines that found it, best rank first.
        public var engines: [String]
        public var score: Double
    }

    /// `k` softens the head of each list: 60 is the usual constant.
    public static func fuse(_ lists: [[Hit]], k: Double = 60) -> [Fused] {
        var byKey: [String: Fused] = [:]
        var bestRank: [String: [String: Int]] = [:]
        var order: [String] = []
        for list in lists {
            for hit in list {
                guard let raw = URL(string: hit.url), let url = URLNormal.normalized(raw), HostGuard.check(url) == .allowed else { continue }
                let key = URLNormal.key(url)
                let add = 1 / (k + Double(hit.rank))
                if var fused = byKey[key] {
                    fused.score += add
                    if !fused.engines.contains(hit.engine) { fused.engines.append(hit.engine) }
                    if fused.snippet.count < hit.snippet.count { fused.snippet = hit.snippet }
                    byKey[key] = fused
                } else {
                    byKey[key] = Fused(url: url, title: hit.title, snippet: hit.snippet, engines: [hit.engine], score: add)
                    order.append(key)
                }
                bestRank[key, default: [:]][hit.engine] = min(bestRank[key]?[hit.engine] ?? .max, hit.rank)
            }
        }
        var fused = order.compactMap { byKey[$0] }
        for index in fused.indices {
            let ranks = bestRank[URLNormal.key(fused[index].url)] ?? [:]
            fused[index].engines.sort { (ranks[$0] ?? .max, $0) < (ranks[$1] ?? .max, $1) }
        }
        // Ties keep the order the results came in.
        let position = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return fused.sorted {
            $0.score != $1.score ? $0.score > $1.score : (position[URLNormal.key($0.url)] ?? 0) < (position[URLNormal.key($1.url)] ?? 0)
        }
    }
}
