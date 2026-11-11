import Foundation

/// One result an engine gave, in the order it gave it.
public struct Hit: Codable, Sendable, Equatable {
    public var url: String
    public var title: String
    public var snippet: String
    public var engine: String
    /// 1 for the engine's first result.
    public var rank: Int

    public init(url: String, title: String, snippet: String, engine: String, rank: Int) {
        self.url = url; self.title = title; self.snippet = snippet; self.engine = engine; self.rank = rank
    }
}

/// A page to read, and why: the person linked it, a linked page links it, or engines found it.
public struct Target: Sendable, Equatable {
    public enum Origin: String, Codable, Sendable { case prompt, link, search }
    public var url: URL
    public var origin: Origin
    /// The engines that found it, best agreement first; empty for a page the person linked.
    public var engines: [String]
    public var title: String?
    public var snippet: String?

    public init(url: URL, origin: Origin, engines: [String] = [], title: String? = nil, snippet: String? = nil) {
        self.url = url; self.origin = origin; self.engines = engines; self.title = title; self.snippet = snippet
    }
}

/// A page as it was read: its words, where they came from, and how.
public struct Page: Sendable, Equatable {
    public var target: Target
    /// Where the request ended, after redirects.
    public var url: URL
    public var title: String
    public var site: String
    public var published: String?
    public var text: String
    /// Drawn by WebKit because the page's words are written by its scripts.
    public var rendered: Bool
    /// Same-site links in the page's main text, for a crawl one step deep.
    public var links: [URL]
    public var status: Int
    public var milliseconds: Int
}

/// A fact found on a page, with the words that say it.
public struct Fact: Codable, Sendable, Equatable {
    public var fact: String
    /// Words from the page itself, so the fact can be checked.
    public var quote: String

    public init(fact: String, quote: String) { self.fact = fact; self.quote = quote }
}

/// A page the answer rests on, numbered as the reply may credit it.
public struct Source: Codable, Sendable, Equatable {
    public var n: Int
    public var title: String
    public var url: String
    /// The host, without `www.`: what "found on …" names.
    public var site: String
    /// How the page was reached: `prompt` (the person linked it), `link` (a linked page links it), `search`.
    public var via: Target.Origin
    /// The engines that found it; empty when the person linked it.
    public var engines: [String]
    public var published: String?
    public var rendered: Bool
    /// The page's words nearest the request, shortened.
    public var excerpt: String
    public var facts: [Fact]

    public init(n: Int, title: String, url: String, site: String, via: Target.Origin, engines: [String], published: String?,
                rendered: Bool, excerpt: String, facts: [Fact]) {
        self.n = n; self.title = title; self.url = url; self.site = site; self.via = via; self.engines = engines
        self.published = published; self.rendered = rendered; self.excerpt = excerpt; self.facts = facts
    }
}

/// What the agent did, step by step, for the reply to account for.
public struct WebWork: Codable, Sendable, Equatable {
    public struct Searched: Codable, Sendable, Equatable {
        public var engine: String
        public var query: String
        public var hits: Int
        public var ms: Int
        /// Why it gave nothing, when it gave nothing.
        public var error: String?

        public init(engine: String, query: String, hits: Int, ms: Int, error: String? = nil) {
            self.engine = engine; self.query = query; self.hits = hits; self.ms = ms; self.error = error
        }
    }
    public struct Crawled: Codable, Sendable, Equatable {
        public var url: String
        public var status: Int
        public var chars: Int
        public var rendered: Bool
        public var ms: Int

        public init(url: String, status: Int, chars: Int, rendered: Bool, ms: Int) {
            self.url = url; self.status = status; self.chars = chars; self.rendered = rendered; self.ms = ms
        }
    }
    public struct Skipped: Codable, Sendable, Equatable {
        public var url: String
        public var why: String

        public init(url: String, why: String) { self.url = url; self.why = why }
    }

    /// The links the prompt carried, as read.
    public var linked: [String] = []
    public var searched: [Searched] = []
    /// Results the engines gave in all, and how many distinct pages they came to.
    public var results: Int = 0
    public var unique: Int = 0
    public var crawled: [Crawled] = []
    /// The first pages passed over, with why; `skippedTotal` counts them all.
    public var skipped: [Skipped] = []
    public var skippedTotal: Int = 0
    /// `model` when the host's model read the pages; `extract` when the nearest sentences were kept instead.
    public var distilled: String = "extract"
    public var seconds: Double = 0

    public init() {}
}
