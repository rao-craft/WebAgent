import Foundation

/// A site's robots.txt, as RFC 9309 reads it: the group for `webagent`, else the group for `*`; the longest rule
/// that matches a path decides, `Allow` winning a tie.
public struct Robots: Sendable, Equatable {
    struct Rule: Sendable, Equatable { var allow: Bool; var pattern: String }
    let rules: [Rule]
    /// Every path is closed: the file could not be read for a reason that says so (a server error).
    let closed: Bool

    public static let open = Robots(rules: [], closed: false)
    public static let shut = Robots(rules: [], closed: true)

    init(rules: [Rule], closed: Bool) { self.rules = rules; self.closed = closed }

    public init(parsing text: String, agent: String = WebIdentity.robotsName) {
        var groups: [(agents: [String], rules: [Rule])] = []
        var agents: [String] = []
        var rules: [Rule] = []
        var inRules = false
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
            guard let colon = line.firstIndex(of: ":") else { continue }
            let field = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            switch field {
            case "user-agent":
                if inRules { groups.append((agents, rules)); agents = []; rules = []; inRules = false }
                agents.append(value.lowercased())
            case "allow", "disallow":
                inRules = true
                if !value.isEmpty { rules.append(Rule(allow: field == "allow", pattern: value)) }
            default:
                continue
            }
        }
        if !agents.isEmpty { groups.append((agents, rules)) }
        let mine = groups.filter { $0.agents.contains { agent.hasPrefix($0) && $0 != "*" } }.flatMap(\.rules)
        let anyone = groups.filter { $0.agents.contains("*") }.flatMap(\.rules)
        self.init(rules: mine.isEmpty ? anyone : mine, closed: false)
    }

    /// Whether the path (with its query) may be read.
    public func allows(_ url: URL) -> Bool {
        if closed { return false }
        var path = url.path(percentEncoded: true)
        if path.isEmpty { path = "/" }
        if let query = url.query(percentEncoded: true) { path += "?" + query }
        var best: Rule?
        for rule in rules where Self.matches(rule.pattern, path) {
            if let current = best {
                if rule.pattern.count > current.pattern.count || (rule.pattern.count == current.pattern.count && rule.allow) { best = rule }
            } else {
                best = rule
            }
        }
        return best?.allow ?? true
    }

    /// `*` matches any run of characters; a final `$` anchors the end.
    static func matches(_ pattern: String, _ path: String) -> Bool {
        var body = pattern
        let anchored = body.hasSuffix("$")
        if anchored { body.removeLast() }
        let expression = "^" + body.split(separator: "*", omittingEmptySubsequences: false)
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
            .joined(separator: ".*") + (anchored ? "$" : "")
        guard let regex = try? NSRegularExpression(pattern: expression) else { return false }
        return regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) != nil
    }
}

/// Each host's robots.txt, read once per call.
public actor RobotsBook {
    private let fetcher: any Fetching
    private var known: [String: Task<Robots, Never>] = [:]

    public init(fetcher: any Fetching) { self.fetcher = fetcher }

    public func robots(for url: URL) async -> Robots {
        guard let scheme = url.scheme, let host = url.host(percentEncoded: true) else { return .open }
        let origin = "\(scheme)://\(host)" + (url.port.map { ":\($0)" } ?? "")
        if let task = known[origin] { return await task.value }
        let fetcher = fetcher
        let task = Task<Robots, Never> {
            guard let robotsURL = URL(string: origin + "/robots.txt") else { return .open }
            do {
                let fetched = try await fetcher.fetch(FetchRequest(url: robotsURL, headers: ["Accept": "text/plain"], timeout: 6, maxBytes: 500_000))
                switch fetched.status {
                case 200..<300: return Robots(parsing: fetched.text)
                case 400..<500: return .open        // no file: every path is open
                default: return .shut               // the server failed: wait, as RFC 9309 says
                }
            } catch FetchError.unrecorded {
                return .open
            } catch {
                return .shut
            }
        }
        known[origin] = task
        return await task.value
    }
}
