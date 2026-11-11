import Foundation
import SwiftSoup

/// A search engine the agent asks: one request, its results in order.
public protocol SearchEngine: Sendable {
    /// The name the work log and "found by" give it.
    var name: String { get }
    func request(for query: String) -> FetchRequest
    /// The results in a response, best first, ranked from 1.
    func parse(_ fetched: Fetched) throws -> [Hit]
}

extension SearchEngine {
    public func search(_ query: String, using fetcher: any Fetching) async throws -> [Hit] {
        var fetched = try await fetcher.fetch(request(for: query))
        // Busy is not no: once more, after a breath.
        if fetched.status == 429 || fetched.status == 503 {
            try await Task.sleep(for: .milliseconds(1_500))
            fetched = try await fetcher.fetch(request(for: query))
        }
        guard (200..<300).contains(fetched.status) else { throw SearchError.status(fetched.status) }
        return try parse(fetched)
    }
}

public enum SearchError: Error, Equatable, CustomStringConvertible {
    case status(Int)
    /// The engine answered with a page that is not its results (a challenge, a consent wall).
    case notResults

    public var description: String {
        switch self {
        case .status(let code): return "answered \(code)"
        case .notResults: return "answered with a page that is not its results"
        }
    }
}

/// The engines every call asks, fixed: four that need no key, and Google when the person has given theirs.
public enum SearchEngines {
    public static let googleKey = "GOOGLE_CSE_KEY"
    public static let googleCX = "GOOGLE_CSE_CX"

    public static func standard(environment: [String: String] = ProcessInfo.processInfo.environment) -> [any SearchEngine] {
        var engines: [any SearchEngine] = [DuckDuckGo(), Brave(), Bing(), Wikipedia()]
        if let key = environment[googleKey], !key.isEmpty, let cx = environment[googleCX], !cx.isEmpty {
            engines.insert(GoogleProgrammable(key: key, cx: cx), at: 0)
        }
        return engines
    }
}

// MARK: - The engines

/// DuckDuckGo's HTML results, which need no script.
public struct DuckDuckGo: SearchEngine {
    public let name = "DuckDuckGo"
    public init() {}

    public func request(for query: String) -> FetchRequest {
        var form = URLComponents()
        form.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "kl", value: "us-en")]
        return FetchRequest(url: URL(string: "https://html.duckduckgo.com/html/")!, method: "POST",
                            body: Data((form.percentEncodedQuery ?? "").utf8),
                            headers: ["Content-Type": "application/x-www-form-urlencoded", "Accept": "text/html"], timeout: 12)
    }

    public func parse(_ fetched: Fetched) throws -> [Hit] {
        let document = try SwiftSoup.parse(fetched.text, fetched.url.absoluteString)
        let blocks = try document.select("div.result:not(.result--ad)")
        if blocks.isEmpty(), try document.select("form#challenge-form, .anomaly-modal").first() != nil { throw SearchError.notResults }
        var hits: [Hit] = []
        for block in blocks {
            guard let link = try block.select("a.result__a").first() else { continue }
            let href = try link.attr("href")
            guard let url = Self.unwrap(href) else { continue }
            let snippet = try block.select(".result__snippet").first()?.text() ?? ""
            hits.append(Hit(url: url, title: try link.text(), snippet: snippet, engine: name, rank: hits.count + 1))
        }
        return hits
    }

    /// A result's own address: DuckDuckGo may route it through `/l/?uddg=…`; an ad goes through `y.js` and is dropped.
    static func unwrap(_ href: String) -> String? {
        let full = href.hasPrefix("//") ? "https:" + href : href
        guard let parts = URLComponents(string: full), let host = parts.host else { return nil }
        if host.hasSuffix("duckduckgo.com") {
            return parts.queryItems?.first { $0.name == "uddg" }?.value
        }
        return full
    }
}

/// Brave Search's results page, which carries its results in the HTML.
public struct Brave: SearchEngine {
    public let name = "Brave"
    public init() {}

    public func request(for query: String) -> FetchRequest {
        var parts = URLComponents(string: "https://search.brave.com/search")!
        parts.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "source", value: "web")]
        return FetchRequest(url: parts.url!, headers: ["Accept": "text/html"], timeout: 12)
    }

    public func parse(_ fetched: Fetched) throws -> [Hit] {
        let document = try SwiftSoup.parse(fetched.text, fetched.url.absoluteString)
        var hits: [Hit] = []
        for block in try document.select("div.snippet[data-type=web]") {
            guard let link = try block.select("a[href^=http]").first() else { continue }
            let url = try link.attr("href")
            guard let host = URL(string: url)?.host, !host.hasSuffix("brave.com") else { continue }
            let heading = try block.select(".search-snippet-title, .title").first()
            let title = try heading.map { try $0.attr("title").isEmpty ? $0.text() : $0.attr("title") } ?? link.text()
            let snippet = try block.select(".generic-snippet .content, .snippet-description").first()?.text() ?? ""
            hits.append(Hit(url: url, title: title, snippet: snippet, engine: name, rank: hits.count + 1))
        }
        return hits
    }
}

/// Bing's results page; each link goes through Bing's `ck/a` with the address in its `u` parameter.
public struct Bing: SearchEngine {
    public let name = "Bing"
    public init() {}

    public func request(for query: String) -> FetchRequest {
        var parts = URLComponents(string: "https://www.bing.com/search")!
        parts.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "setlang", value: "en"),
                            URLQueryItem(name: "cc", value: "US")]
        return FetchRequest(url: parts.url!, headers: ["Accept": "text/html"], timeout: 12)
    }

    public func parse(_ fetched: Fetched) throws -> [Hit] {
        let document = try SwiftSoup.parse(fetched.text, fetched.url.absoluteString)
        var hits: [Hit] = []
        for block in try document.select("li.b_algo") {
            guard let link = try block.select("h2 a[href]").first(), let url = Self.unwrap(try link.attr("href")) else { continue }
            let snippet = try block.select(".b_caption p, p[class^=b_lineclamp], .b_paractl").first()?.text() ?? ""
            hits.append(Hit(url: url, title: try link.text(), snippet: snippet, engine: name, rank: hits.count + 1))
        }
        return hits
    }

    /// `https://www.bing.com/ck/a?…&u=a1<base64url>&…` → the address; any other link as it is.
    static func unwrap(_ href: String) -> String? {
        guard let parts = URLComponents(string: href), let host = parts.host else { return nil }
        guard host.hasSuffix("bing.com") else { return href }
        guard let u = parts.queryItems?.first(where: { $0.name == "u" })?.value, u.hasPrefix("a1") else { return nil }
        var base64 = String(u.dropFirst(2)).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64), let decoded = String(data: data, encoding: .utf8), decoded.hasPrefix("http") else { return nil }
        return decoded
    }
}

/// Wikipedia's own search, in English, through its REST API.
public struct Wikipedia: SearchEngine {
    public let name = "Wikipedia"
    public init() {}

    public func request(for query: String) -> FetchRequest {
        var parts = URLComponents(string: "https://en.wikipedia.org/w/rest.php/v1/search/page")!
        parts.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "5")]
        return FetchRequest(url: parts.url!, headers: ["Accept": "application/json"], timeout: 10)
    }

    struct Response: Decodable {
        struct Page: Decodable { var key: String; var title: String; var excerpt: String?; var description: String? }
        var pages: [Page]
    }

    public func parse(_ fetched: Fetched) throws -> [Hit] {
        let response = try JSONDecoder().decode(Response.self, from: fetched.data)
        return try response.pages.enumerated().map { index, page in
            let excerpt = try SwiftSoup.parse(page.excerpt ?? "").text()
            let snippet = [page.description, excerpt].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: ". ")
            let key = page.key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? page.key
            return Hit(url: "https://en.wikipedia.org/wiki/\(key)", title: page.title, snippet: snippet, engine: name, rank: index + 1)
        }
    }
}

/// Google, through a Programmable Search Engine the person set up: their key and engine id in the environment.
public struct GoogleProgrammable: SearchEngine {
    public let name = "Google"
    let key: String
    let cx: String

    public init(key: String, cx: String) { self.key = key; self.cx = cx }

    public func request(for query: String) -> FetchRequest {
        var parts = URLComponents(string: "https://www.googleapis.com/customsearch/v1")!
        parts.queryItems = [URLQueryItem(name: "key", value: key), URLQueryItem(name: "cx", value: cx),
                            URLQueryItem(name: "q", value: query), URLQueryItem(name: "num", value: "10")]
        return FetchRequest(url: parts.url!, headers: ["Accept": "application/json"], timeout: 10)
    }

    struct Response: Decodable {
        struct Item: Decodable { var link: String; var title: String; var snippet: String? }
        var items: [Item]?
    }

    public func parse(_ fetched: Fetched) throws -> [Hit] {
        let response = try JSONDecoder().decode(Response.self, from: fetched.data)
        return (response.items ?? []).enumerated().map { index, item in
            Hit(url: item.link, title: item.title, snippet: item.snippet ?? "", engine: name, rank: index + 1)
        }
    }
}
