import Foundation

/// How far a crawl goes.
public struct CrawlLimits: Sendable {
    /// Pages read, at most.
    public var pages: Int = 6
    /// Reads at once.
    public var concurrency: Int = 4
    /// No read starts after this many seconds.
    public var budget: TimeInterval = 45
    public var requestTimeout: TimeInterval = 10
    public var renderTimeout: TimeInterval = 15
    public var maxBytes: Int = 2 << 20

    public init(pages: Int = 6) { self.pages = pages }
}

/// What a crawl read and what it passed over.
public struct CrawlOutcome: Sendable {
    public var pages: [Page] = []
    public var crawled: [WebWork.Crawled] = []
    public var skipped: [WebWork.Skipped] = []
    /// Skips the network caused (nothing answered, or not in time), as against a page that answered and was gone,
    /// closed or empty.
    public var unreachable = 0
}

/// The isolated crawl: the prompt's links first, then (one step deep, when asked) the same-site links they carry,
/// then the engines' results in their fused order until the page cap is met or the budget spent.
///
/// PIN: THE PERSON'S LINKS ARE READ AS ASKED. A page the person linked is a request, not a crawl, so robots.txt is
/// kept for every page the agent found on its own (results, links one step deep) and not for the person's own.
/// Every page, theirs or found, must be a public host.
public struct Crawler: Sendable {
    let fetcher: any Fetching
    let renderer: any Rendering
    let limits: CrawlLimits
    let note: @Sendable (String) -> Void
    let robots: RobotsBook

    public init(fetcher: any Fetching, renderer: any Rendering, limits: CrawlLimits = CrawlLimits(),
                note: @escaping @Sendable (String) -> Void = { _ in }) {
        self.fetcher = fetcher; self.renderer = renderer; self.limits = limits; self.note = note
        robots = RobotsBook(fetcher: fetcher)
    }

    public func crawl(prompt: [Target], search: [Target], depth: Int, terms: [String]) async -> CrawlOutcome {
        let started = Date()
        var outcome = CrawlOutcome()
        var seen = Set<String>()

        let linked = Array(dedupe(prompt, &seen).prefix(limits.pages))
        await read(linked, into: &outcome, wanted: linked.count, started: started)

        if depth > 0, outcome.pages.count < limits.pages {
            let quota = min(3, limits.pages - outcome.pages.count)
            let links = outcome.pages.filter { $0.target.origin == .prompt }.flatMap(\.links)
            let ranked = rankLinks(links, terms: terms).map { Target(url: $0, origin: .link) }
            await read(dedupe(ranked, &seen), into: &outcome, wanted: quota, started: started)
        }

        if outcome.pages.count < limits.pages {
            await read(dedupe(search, &seen), into: &outcome, wanted: limits.pages - outcome.pages.count, started: started)
        }
        return outcome
    }

    private func dedupe(_ targets: [Target], _ seen: inout Set<String>) -> [Target] {
        targets.filter { seen.insert(URLNormal.key($0.url)).inserted }
    }

    /// Same-site links whose address shares the most words with the request first.
    func rankLinks(_ links: [URL], terms: [String]) -> [URL] {
        let scored = links.enumerated().map { index, url -> (URL, Int, Int) in
            let path = url.path(percentEncoded: false).lowercased()
            return (url, terms.filter { path.contains($0) }.count, index)
        }
        return scored.filter { $0.1 > 0 }.sorted { ($0.1, -$0.2) > ($1.1, -$1.2) }.map(\.0)
    }

    /// Reads candidates in order, `concurrency` at once, until `wanted` pages are read, the candidates run out or
    /// the budget is spent. A candidate that fails makes room for the next.
    private func read(_ candidates: [Target], into outcome: inout CrawlOutcome, wanted: Int, started: Date) async {
        guard wanted > 0, !candidates.isEmpty else { return }
        var queue = candidates[...]
        var read = 0
        var inFlight = 0
        await withTaskGroup(of: (Target, Result<Page, Skip>).self) { group in
            func launch() {
                while inFlight < limits.concurrency, read + inFlight < wanted, let next = queue.popFirst(),
                      Date().timeIntervalSince(started) < limits.budget {
                    inFlight += 1
                    group.addTask { (next, await self.page(next)) }
                }
            }
            launch()
            while let (target, result) = await group.next() {
                inFlight -= 1
                switch result {
                case .success(let page):
                    read += 1
                    outcome.pages.append(page)
                    outcome.crawled.append(WebWork.Crawled(url: page.url.absoluteString, status: page.status, chars: page.text.count,
                                                           rendered: page.rendered, ms: page.milliseconds))
                    note("Read \(outcome.pages.count)/\(limits.pages): \(URLNormal.site(page.url))\(page.rendered ? " (drawn in WebKit)" : "")")
                case .failure(let skip):
                    outcome.skipped.append(WebWork.Skipped(url: target.url.absoluteString, why: skip.why))
                    if skip.network { outcome.unreachable += 1 }
                    note("Skipped \(URLNormal.site(target.url)): \(skip.why)")
                }
                if Task.isCancelled { group.cancelAll(); return }
                launch()
            }
        }
    }

    struct Skip: Error {
        var why: String
        var network = false
    }

    /// One page: its host checked, its robots kept (unless the person linked it), fetched, read, drawn when its
    /// words need scripts.
    func page(_ target: Target) async -> Result<Page, Skip> {
        let clock = ContinuousClock.now
        let verdict = fetcher.resolvesHosts ? await HostGuard.checkResolving(target.url) : HostGuard.check(target.url)
        if case .refused(let why) = verdict { return .failure(Skip(why: why)) }
        if target.origin != .prompt, !(await robots.robots(for: target.url).allows(target.url)) {
            return .failure(Skip(why: "robots.txt asks not to"))
        }
        let fetched: Fetched
        do {
            fetched = try await fetcher.fetch(FetchRequest(url: target.url, timeout: limits.requestTimeout, maxBytes: limits.maxBytes))
        } catch let error as FetchError {
            return .failure(Skip(why: "\(error)", network: error.isNetwork))
        } catch {
            return .failure(Skip(why: "\(error)", network: true))
        }
        guard (200..<300).contains(fetched.status) else { return .failure(Skip(why: "answered \(fetched.status)")) }

        let mime = (fetched.mimeType ?? Self.guessType(fetched)).lowercased()
        var readable: Readable
        var rendered = false
        switch mime {
        case "text/html", "application/xhtml+xml":
            readable = Readable(html: fetched.text, url: fetched.url)
            if readable.scripted || readable.text.count < 200,
               let drawn = try? await renderer.render(fetched.url, timeout: limits.renderTimeout) {
                var redrawn = Readable(html: drawn.html, url: drawn.url)
                if redrawn.text.count < 200, drawn.text.count > redrawn.text.count { redrawn.text = Readable.clean(drawn.text) }
                if redrawn.text.count > readable.text.count {
                    if redrawn.title.isEmpty { redrawn.title = readable.title }
                    readable = redrawn
                    rendered = true
                }
            }
        case "application/pdf":
            guard let pdf = Readable.pdf(fetched.data, url: fetched.url) else { return .failure(Skip(why: "a PDF with no text")) }
            readable = pdf
        case _ where mime.hasPrefix("text/") || mime == "application/json" || mime.hasSuffix("+json"):
            readable = Readable(title: fetched.url.lastPathComponent, site: nil, published: nil, text: String(fetched.text.prefix(60_000)),
                                links: [], scripted: false)
        default:
            return .failure(Skip(why: "a \(mime) file"))
        }
        guard readable.text.count >= 40 else { return .failure(Skip(why: "no readable text")) }
        let elapsed = ContinuousClock.now - clock
        let ms = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
        return .success(Page(target: target, url: fetched.url, title: readable.title.isEmpty ? (target.title ?? URLNormal.site(fetched.url)) : readable.title,
                             site: URLNormal.site(fetched.url), published: readable.published, text: readable.text, rendered: rendered,
                             links: readable.links, status: fetched.status, milliseconds: ms))
    }

    static func guessType(_ fetched: Fetched) -> String {
        if fetched.data.starts(with: Data("%PDF".utf8)) { return "application/pdf" }
        let head = String(decoding: fetched.data.prefix(512), as: UTF8.self).lowercased()
        return head.contains("<html") || head.contains("<!doctype html") ? "text/html" : "text/plain"
    }
}
