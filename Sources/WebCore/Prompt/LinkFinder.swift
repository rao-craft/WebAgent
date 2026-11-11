import Foundation

/// The links a prompt carries, and the words it asks with once they are taken out.
public enum LinkFinder {
    /// Every http(s) link in `text`, as written or bare (`swift.org/blog`), normalized, in order, once each.
    public static func links(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var found: [URL] = []
        var seen = Set<String>()
        for match in detector.matches(in: text, options: [], range: range) {
            guard let url = match.url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  let normal = URLNormal.normalized(url) else { continue }
            if seen.insert(URLNormal.key(normal)).inserted { found.append(normal) }
        }
        return found
    }

    /// The links in `strings` (the call's own `urls`), each read as a link even when written bare.
    public static func links(from strings: [String]) -> [URL] {
        var found: [URL] = []
        var seen = Set<String>()
        for raw in strings {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let written = trimmed.contains("://") ? trimmed : "https://" + trimmed
            guard let url = URL(string: written), let normal = URLNormal.normalized(url) else { continue }
            if seen.insert(URLNormal.key(normal)).inserted { found.append(normal) }
        }
        return found
    }

    /// What the prompt asks, without its links or agent tags (`$web`), as a search engine would take it.
    public static func query(from ask: String) -> String {
        var words = ask
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for match in detector.matches(in: ask, options: [], range: NSRange(ask.startIndex..., in: ask)).reversed() {
                if let range = Range(match.range, in: words) { words.replaceSubrange(range, with: " ") }
            }
        }
        let kept = words.split(whereSeparator: \.isWhitespace)
            .filter { !$0.hasPrefix("$") && !$0.hasPrefix("#") && !$0.hasPrefix("@") }
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-–—"))
        return String(kept.prefix(240))
    }
}

/// One spelling per page: what the crawl fetches and what fusion counts as the same result.
public enum URLNormal {
    /// Parameters that say who sent a reader, not what the page is.
    static let tracking: Set<String> = ["gclid", "fbclid", "msclkid", "dclid", "yclid", "mc_cid", "mc_eid", "ref", "ref_src", "igshid", "si"]

    /// The URL without its fragment or tracking parameters, its scheme and host lowercased.
    public static func normalized(_ url: URL) -> URL? {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: true), let host = parts.host, !host.isEmpty else { return nil }
        parts.scheme = parts.scheme?.lowercased()
        parts.host = host.lowercased()
        parts.fragment = nil
        if (parts.scheme == "https" && parts.port == 443) || (parts.scheme == "http" && parts.port == 80) { parts.port = nil }
        if let items = parts.queryItems {
            let kept = items.filter { !$0.name.lowercased().hasPrefix("utm_") && !tracking.contains($0.name.lowercased()) }
            parts.queryItems = kept.isEmpty ? nil : kept
        }
        if parts.path.isEmpty { parts.path = "/" }
        // Trailing punctuation a sentence put after a link is not the link's.
        while let last = parts.path.last, parts.query == nil, ".,;:!?)]}'\"".contains(last) {
            // A closing bracket is the link's when the link opened it: `Swift_(programming_language)`.
            if let open = ["(": ")", "[": "]", "{": "}"].first(where: { $0.value == String(last) })?.key,
               parts.path.filter({ String($0) == open }).count >= parts.path.filter({ $0 == last }).count {
                break
            }
            parts.path.removeLast()
        }
        return parts.url
    }

    /// The same page however it was written: no scheme, no `www.`, no trailing slash.
    public static func key(_ url: URL) -> String {
        var host = url.host(percentEncoded: false)?.lowercased() ?? ""
        if host.hasPrefix("www.") { host.removeFirst(4) }
        var path = url.path(percentEncoded: true)
        if path.hasSuffix("/") { path.removeLast() }
        let query = url.query(percentEncoded: true).map { "?" + $0 } ?? ""
        return host + path + query
    }

    /// The host as "found on …" names it: `swift.org`, not `www.swift.org`.
    public static func site(_ url: URL) -> String {
        var host = url.host(percentEncoded: false)?.lowercased() ?? ""
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }
}
