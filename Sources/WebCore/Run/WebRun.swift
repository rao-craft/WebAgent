import Foundation

/// What a run is asked: the person's words, the search the model phrased, the links, how far to go.
public struct WebRequest: Sendable {
    public var ask: String?
    public var query: String?
    public var urls: [String]
    /// False: read the links alone, search nothing.
    public var search: Bool
    public var depth: Int
    public var pages: Int

    public init(ask: String? = nil, query: String? = nil, urls: [String] = [], search: Bool = true, depth: Int = 0, pages: Int = 6) {
        self.ask = ask; self.query = query; self.urls = urls; self.search = search; self.depth = depth; self.pages = pages
    }
}

/// Something the run could only do in part, by kind: `engine`, `crawl`, `model`, `trim`.
public struct WebProblem: Sendable, Equatable {
    public var kind: String
    public var text: String

    public init(kind: String, text: String) { self.kind = kind; self.text = text }
}

/// What a run found and did.
public struct WebOutcome: Sendable {
    public var query: String?
    public var sources: [Source]
    public var work: WebWork
    public var notes: [String]
    public var problems: [WebProblem]

    public init(query: String?, sources: [Source], work: WebWork, notes: [String], problems: [WebProblem]) {
        self.query = query; self.sources = sources; self.work = work; self.notes = notes; self.problems = problems
    }
}

public enum WebError: Error, Equatable, CustomStringConvertible {
    /// Nothing to search for and no link to read.
    case nothingAsked
    /// Nothing answered at all: the network failed, not the pages. Try later.
    case unreachable(String)
    /// The engines answered without results (busy, or turning automated readers away). Try later.
    case enginesDown(String)
    /// Every link answered and none could be read: gone, private, closed or empty. The call is the one to fix.
    case unreadable(String)

    public var description: String {
        switch self {
        case .nothingAsked:
            return "There is nothing to look up: give `query` (what to search for) or `urls` (pages to read), or ask with words or a link."
        case .unreachable(let why):
            return "Nothing on the web answered this Mac (\(why)): it looks offline. Try again when it is online."
        case .enginesDown(let why):
            return "No search engine gave results (\(why)). Try again in a minute, or give `urls` to read pages directly."
        case .unreadable(let why):
            return "No page could be read: \(why). Do not call web again with the same link: check the address, or search instead "
                + "(give `query` and leave `search` out)."
        }
    }
}

/// The whole run: links found, engines asked, results fused, the crawl, the facts, the sources numbered.
public struct WebRun: Sendable {
    public var engines: [any SearchEngine]
    public var fetcher: any Fetching
    public var renderer: any Rendering
    public var model: (any FactModel)?
    public var note: @Sendable (String) -> Void

    public init(engines: [any SearchEngine] = SearchEngines.standard(), fetcher: any Fetching = IsolatedFetcher(),
                renderer: any Rendering = WebKitRenderer(), model: (any FactModel)? = nil, note: @escaping @Sendable (String) -> Void = { _ in }) {
        self.engines = engines; self.fetcher = fetcher; self.renderer = renderer; self.model = model; self.note = note
    }

    /// The pages a call may read at most.
    public static let pageRange = 1...12
    /// Characters of a page's words a model reads.
    static let modelExcerpt = 2_400
    /// Pages passed over that the answer names; the rest are counted.
    static let skippedKept = 10
    /// Characters of a page's words the answer carries.
    static let answerExcerpt = 700

    public func run(_ request: WebRequest) async throws -> WebOutcome {
        let started = Date()
        var work = WebWork()
        var notes: [String] = []
        var problems: [WebProblem] = []

        let links = (LinkFinder.links(from: request.urls) + LinkFinder.links(in: request.ask ?? ""))
            .reduce(into: [URL]()) { kept, url in if !kept.contains(where: { URLNormal.key($0) == URLNormal.key(url) }) { kept.append(url) } }
        let linkKeys = Set(links.map(URLNormal.key))
        work.linked = links.map(\.absoluteString)
        let asked = request.query?.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = (asked?.isEmpty == false ? asked : nil) ?? request.ask.map(LinkFinder.query(from:)).flatMap { $0.isEmpty ? nil : $0 }
        var searching = request.search && query != nil
        guard searching || !links.isEmpty else { throw WebError.nothingAsked }
        let terms = Distiller.terms([query, request.ask].compactMap { $0 }.joined(separator: " "))
        if !links.isEmpty { note("Reading \(links.count == 1 ? "the link" : "the \(links.count) links") in the prompt") }

        // The engines, all at once.
        var fused: [Fusion.Fused] = []
        var enginesOffline = false
        if searching, let query {
            (fused, enginesOffline) = await search(query, into: &work, problems: &problems)
            if links.isEmpty, fused.isEmpty, work.searched.allSatisfy({ $0.error != nil && $0.error != "no results" }) {
                let why = work.searched.map { "\($0.engine) \($0.error ?? "")" }.joined(separator: "; ")
                throw enginesOffline ? WebError.unreachable(why) : WebError.enginesDown(why)
            }
        }

        // The crawl.
        var limits = CrawlLimits(pages: min(max(request.pages, Self.pageRange.lowerBound), Self.pageRange.upperBound))
        limits.pages = max(limits.pages, min(links.count, Self.pageRange.upperBound))
        let crawler = Crawler(fetcher: fetcher, renderer: renderer, limits: limits, note: note)
        var crawl = await crawler.crawl(
            prompt: links.map { Target(url: $0, origin: .prompt) },
            search: Self.targets(fused), depth: min(max(request.depth, 0), 1), terms: terms)

        // Every link failed and nothing was searched: a link that is gone or private is no reason to stop when
        // there are words to search for, so the engines are asked instead, and the answer says so.
        if crawl.pages.isEmpty, !links.isEmpty, !searching, let query {
            let failed = Self.list(crawl.skipped.map { "\($0.url) \($0.why)" })
            note("\(links.count == 1 ? "The link" : "No link") could not be read; searching for “\(query)” instead")
            notes.append("\(links.count == 1 ? "The link could not be read" : "None of the links could be read") (\(failed)), so the engines were searched for “\(query)” instead.")
            searching = true
            (fused, enginesOffline) = await search(query, into: &work, problems: &problems)
            fused.removeAll { linkKeys.contains(URLNormal.key($0.url)) }
            let more = await crawler.crawl(prompt: [], search: Self.targets(fused), depth: 0, terms: terms)
            crawl.pages += more.pages
            crawl.crawled += more.crawled
            crawl.skipped += more.skipped
            crawl.unreachable += more.unreachable
        }
        work.crawled = crawl.crawled
        work.skipped = Array(crawl.skipped.prefix(Self.skippedKept))
        work.skippedTotal = crawl.skipped.count

        if crawl.pages.isEmpty, !links.isEmpty, fused.isEmpty {
            let linkSkips = crawl.skipped.filter { skip in URL(string: skip.url).map { linkKeys.contains(URLNormal.key($0)) } ?? false }
            let offline = crawl.unreachable == crawl.skipped.count && (work.searched.isEmpty || enginesOffline)
            if offline {
                throw WebError.unreachable(linkSkips.map { "\($0.url) \($0.why)" }.joined(separator: "; "))
            }
            var why = Self.list(linkSkips.map { "\($0.url) \(Self.explained($0.why))" })
            if searching, let query { why += "; and the search for “\(query)” found nothing to read" }
            throw WebError.unreadable(why)
        }

        // The pages in the order the answer numbers them: the person's links, their links, then the results.
        let order: [Target.Origin: Int] = [.prompt: 0, .link: 1, .search: 2]
        let asWritten = Dictionary(links.enumerated().map { (URLNormal.key($1), $0) }, uniquingKeysWith: { a, _ in a })
        let asFused = Dictionary(fused.enumerated().map { (URLNormal.key($1.url), $0) }, uniquingKeysWith: { a, _ in a })
        let asRead = Dictionary(crawl.pages.enumerated().map { (URLNormal.key($1.target.url), $0) }, uniquingKeysWith: { a, _ in a })
        func place(_ page: Page) -> (Int, Int) {
            let key = URLNormal.key(page.target.url)
            switch page.target.origin {
            case .prompt: return (0, asWritten[key] ?? 0)
            case .link: return (order[.link]!, asRead[key] ?? 0)
            case .search: return (order[.search]!, asFused[key] ?? 0)
            }
        }
        let pages = crawl.pages.sorted { place($0) < place($1) }

        // The facts: the model's when there is one and it answers, the nearest sentences otherwise.
        var facts: [Int: [Fact]] = [:]
        if let model, !pages.isEmpty {
            note("Reading \(pages.count) page\(pages.count == 1 ? "" : "s") for facts with the model")
            let excerpts = pages.enumerated().map { index, page in
                PageExcerpt(n: index + 1, site: page.site, title: page.title,
                            text: Distiller.excerpt(page.text, terms: terms, limit: Self.modelExcerpt))
            }
            do {
                let found = try await model.facts(ask: request.ask ?? query ?? "", excerpts: excerpts)
                var dropped = 0
                for (n, list) in found where (1...pages.count).contains(n) {
                    let text = pages[n - 1].text
                    let kept = list.filter { Distiller.quoted($0.quote, in: text) }
                    dropped += list.count - kept.count
                    if !kept.isEmpty { facts[n] = Array(kept.prefix(6)) }
                }
                work.distilled = "model"
                if dropped > 0 {
                    problems.append(WebProblem(kind: "model", text: "\(dropped) fact\(dropped == 1 ? "" : "s") the model gave did not quote its page and were left out."))
                }
            } catch {
                problems.append(WebProblem(kind: "model", text: "The model could not read the pages (\(error)); the sentences nearest the request are kept instead."))
            }
        }
        if work.distilled == "extract" {
            for (index, page) in pages.enumerated() {
                let found = Distiller.extract(page.text, terms: terms)
                if !found.isEmpty { facts[index + 1] = found }
            }
        }
        let factCount = facts.values.reduce(0) { $0 + $1.count }
        if !pages.isEmpty { note("\(factCount) fact\(factCount == 1 ? "" : "s") from \(pages.count) page\(pages.count == 1 ? "" : "s")") }

        let sources = pages.enumerated().map { index, page in
            Source(n: index + 1, title: page.title, url: page.url.absoluteString, site: page.site, via: page.target.origin,
                   engines: page.target.engines, published: page.published, rendered: page.rendered,
                   excerpt: Distiller.excerpt(page.text, terms: terms, limit: Self.answerExcerpt), facts: facts[index + 1] ?? [])
        }

        work.seconds = (Date().timeIntervalSince(started) * 10).rounded() / 10
        notes += Self.notes(query: searching ? query : nil, work: work, sources: sources, skips: Self.reasons(crawl.skipped))
        return WebOutcome(query: searching ? query : nil, sources: sources, work: work, notes: notes, problems: problems)
    }

    /// What the model should know, one sentence each: what was done, then how to answer from it.
    static func notes(query: String?, work: WebWork, sources: [Source], skips: String = "") -> [String] {
        var notes: [String] = []
        if let query {
            let answered = work.searched.filter { $0.hits > 0 }.map(\.engine)
            notes.append("Searched \(list(work.searched.map(\.engine))) for “\(query)”: \(work.results) results from \(list(answered.isEmpty ? ["none"] : answered)), \(work.unique) distinct pages.")
        }
        let read = sources.filter { $0.via == .prompt }.map(\.url)
        if !read.isEmpty {
            notes.append("Read \(read.count == 1 ? "the link" : "\(read.count) links") in the prompt directly: \(read.joined(separator: ", ")).")
        }
        let drawn = work.crawled.filter(\.rendered).count
        let sites = list(Array(NSOrderedSet(array: sources.map(\.site)).compactMap { $0 as? String }))
        notes.append("Read \(work.crawled.count) page\(work.crawled.count == 1 ? "" : "s") in an isolated crawl\(sources.isEmpty ? "" : " (\(sites))")"
                     + (drawn > 0 ? ", \(drawn) drawn in WebKit because \(drawn == 1 ? "its" : "their") words need JavaScript" : "")
                     + (work.skippedTotal == 0 ? "" : "; skipped \(work.skippedTotal) (\(skips))") + ".")
        if sources.isEmpty {
            notes.append("No page could be read: say so, and answer only from what is known without the web, saying that too.")
            return notes
        }
        notes.append("Answer from `sources`: credit each fact taken from them inline as (found on <site>), e.g. (found on \(sources[0].site)), linking the page where it helps; never credit a page that is not in `sources`, and say plainly what they do not cover.")
        notes.append("End the reply with a short “Web work” section from `work`: the engines searched and the query, the results and distinct pages, the pages read by site, and anything skipped.")
        return notes
    }

    /// Why pages were passed over, by kind and count, most first: "3 timed out, 1 robots.txt asks not to".
    static func reasons(_ skipped: [WebWork.Skipped]) -> String {
        var counts: [String: Int] = [:]
        for skip in skipped {
            let kind = skip.why.components(separatedBy: ": ").first ?? skip.why
            counts[kind, default: 0] += 1
        }
        let sorted = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        var parts = sorted.prefix(4).map { "\($0.value) \($0.key)" }
        let rest = sorted.dropFirst(4).reduce(0) { $0 + $1.value }
        if rest > 0 { parts.append("\(rest) for other reasons") }
        return parts.joined(separator: ", ")
    }

    /// The engines asked at once, their results fused, each engine's answer logged; whether every failure was the
    /// network's.
    func search(_ query: String, into work: inout WebWork, problems: inout [WebProblem]) async -> ([Fusion.Fused], Bool) {
        note("Searching \(Self.list(engines.map(\.name))) for “\(query)”")
        let fetcher = fetcher
        let results = await withTaskGroup(of: (Int, String, Result<[Hit], Error>, Int).self) { group in
            for (index, engine) in engines.enumerated() {
                group.addTask {
                    let clock = ContinuousClock.now
                    do {
                        let hits = try await engine.search(query, using: fetcher)
                        return (index, engine.name, .success(hits), Self.ms(since: clock))
                    } catch {
                        return (index, engine.name, .failure(error), Self.ms(since: clock))
                    }
                }
            }
            var all: [(Int, String, Result<[Hit], Error>, Int)] = []
            for await result in group { all.append(result) }
            return all.sorted { $0.0 < $1.0 }
        }
        var lists: [[Hit]] = []
        var failures = 0
        var offline = 0
        for (_, name, result, ms) in results {
            switch result {
            case .success(let hits):
                lists.append(hits)
                work.searched.append(.init(engine: name, query: query, hits: hits.count, ms: ms, error: hits.isEmpty ? "no results" : nil))
                if hits.isEmpty { problems.append(WebProblem(kind: "engine", text: "\(name) gave no results.")) }
            case .failure(let error):
                failures += 1
                if (error as? FetchError)?.isNetwork ?? (error is URLError) { offline += 1 }
                work.searched.append(.init(engine: name, query: query, hits: 0, ms: ms, error: "\(error)"))
                problems.append(WebProblem(kind: "engine", text: "\(name) gave nothing: \(error)."))
            }
        }
        let fused = Fusion.fuse(lists)
        work.results += lists.reduce(0) { $0 + $1.count }
        work.unique += fused.count
        note("\(lists.reduce(0) { $0 + $1.count }) results, \(fused.count) distinct pages")
        return (fused, failures > 0 && offline == failures && lists.allSatisfy(\.isEmpty))
    }

    static func targets(_ fused: [Fusion.Fused]) -> [Target] {
        fused.map { Target(url: $0.url, origin: .search, engines: $0.engines, title: $0.title, snippet: $0.snippet) }
    }

    /// A skip's reason as the model can act on it.
    static func explained(_ why: String) -> String {
        switch why {
        case "answered 404", "answered 410":
            return "\(why): no such page, or a private one (the crawl signs in nowhere)"
        case "answered 401", "answered 403":
            return "\(why): it needs a login, or turns automated readers away"
        case "the host does not resolve":
            return "\(why): a wrong address, or this Mac is offline"
        default:
            return why
        }
    }

    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + " and " + items.last!
        }
    }

    static func ms(since start: ContinuousClock.Instant) -> Int {
        let elapsed = ContinuousClock.now - start
        return Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }
}
