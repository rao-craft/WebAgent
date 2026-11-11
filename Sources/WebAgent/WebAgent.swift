//  WHAT: The web, read for a request, as a Granite agent package. A call carries what to search for and the links to
//        read (the person's own links come with their ask as well); the run asks four search engines at once, fuses
//        their results, reads the links and the best results in an isolated crawl, draws a page in WebKit when its
//        words need JavaScript, and keeps the facts each page holds with the words that say them.
//  IN:   Input: the search, the links, whether to search at all, one step deeper or not, how many pages.
//  OUT:  WebResult: the sources numbered, each with its site, excerpt and facts; the work done, step by step; notes
//        that say how to credit the sources in the reply and account for the work.
//  PIN:  THE HOST MODEL IS OFFERED, NEVER NEEDED. With the host's model the facts are the model's, each kept only when
//        its quote is the page's own words; without one, the sentences nearest the request are kept as they are.
//  PIN:  NOTHING WRITTEN. The answer is the work: no file is made, so a call owes no build and changes no project.
//        `WEB_FIXTURES_DIR` reads a recorded web instead, for tests and for a Mac without a network.

import Foundation
import GraniteAgents
import WebCore

public struct WebAgent: GraniteAgentPackage {
    public struct Input: Codable, Sendable {
        /// What to search for, phrased for a search engine; left out, the person's own words are searched.
        public var query: String?
        /// Pages to read directly; the links in the person's ask are read as well.
        public var urls: [String]?
        /// False reads the links alone and searches nothing.
        public var search: Bool?
        /// 1 also reads up to three same-site pages the linked pages link to.
        public var depth: Int?
        /// Pages to read, 1 to 12: 6 when left out.
        public var pages: Int?

        public init(query: String? = nil, urls: [String]? = nil, search: Bool? = nil, depth: Int? = nil, pages: Int? = nil) {
            self.query = query; self.urls = urls; self.search = search; self.depth = depth; self.pages = pages
        }
    }

    public typealias Event = WebFrame
    public typealias Output = WebResult
    public typealias Compute = Void

    public static let word = "web"
    public static let summary = "looks a request up on the web: it searches DuckDuckGo, Brave, Bing and Wikipedia at once, reads the links in the prompt and the best results in an isolated crawl (WebKit for pages that need JavaScript), and answers with the facts it found, each with the page it came from, and the work it did."
    public static let fields = [
        "query": "what to search for, phrased for a search engine: the subject, names, versions, dates; left out, the person's own words are searched",
        "urls": "pages to read directly, when the person named or linked them; the links in the person's message are read without being listed here",
        "search": "false reads the links alone and searches nothing; left out, the engines are searched too",
        "depth": "1 also reads up to three pages on the same site that the linked pages link to, nearest the request first; 0 or left out reads only the pages themselves",
        "pages": "how many pages to read, 1 to 12; 6 when left out",
    ]
    public static let guide = """
        Tag web to look something up on the web: news, releases, documentation, prices, anything newer than what you \
        know or a page the person linked. Call it before answering: it searches DuckDuckGo, Brave, Bing and Wikipedia \
        at once (and Google when the person has a Programmable Search key), fuses their results, and reads the links in \
        the person's message and the best results in an isolated crawl: no cookies, no cache, no login, public sites \
        only, robots.txt kept for every page it finds on its own. Give `query` the search as a search engine wants it \
        (`{"query": "Swift 6.4 release notes"}`); the links in the person's message are read without being listed, and \
        `urls` adds others. `search: false` reads the links alone; `depth: 1` also reads a few pages on the same site \
        the links point to; `pages` reads more or fewer than 6. The answer's `sources` are numbered pages, each with \
        its `site`, an `excerpt` and `facts` whose `quote` is the page's own words; `work` is what it did, step by step. \
        Answer from the sources and credit each fact inline as (found on <site>), e.g. (found on swift.org); never \
        credit a page that is not in `sources`, never invent one, and say plainly what they do not cover. End the reply \
        with a short "Web work" section: the engines searched and the query, how many results and pages, the pages \
        read by site, and anything skipped. It writes no file. A call with no words and no link is refused; a web out \
        of reach is refused with try-later.
        """
    /// A call is the network's time, not the cores': two at once.
    public static let lanes: Int? = 2

    public static func output(from events: [WebFrame]) -> WebResult? { events.compactMap(\.result).last }

    public init() {}

    public func run(_ input: Input, context: Context) -> AsyncThrowingStream<WebFrame, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let recorded = RecordedFetcher.fromEnvironment()
                    let web = WebRun(engines: SearchEngines.standard(), fetcher: recorded ?? IsolatedFetcher(),
                                     renderer: recorded == nil ? WebKitRenderer() : NoRenderer(),
                                     model: context.host.model.map { HostFacts(model: $0) }, note: context.host.note)
                    let result = try await Self.perform(input, ask: context.host.ask, web: web)
                    continuation.yield(.answered(result))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The whole call: the run, the answer fitted to what a host passes on.
    public static func perform(_ input: Input, ask: String?, web: WebRun) async throws -> WebResult {
        let request = WebRequest(ask: ask, query: input.query, urls: input.urls ?? [], search: input.search ?? true,
                                 depth: input.depth ?? 0, pages: input.pages ?? 6)
        let outcome = try await web.run(request)
        return WebResult(outcome).fitted()
    }
}
