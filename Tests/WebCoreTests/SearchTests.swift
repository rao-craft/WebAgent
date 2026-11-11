import Foundation
import XCTest
@testable import WebCore

/// Each engine read from a results page it gave, and the engines' results fused.
final class SearchTests: XCTestCase {
    func testDuckDuckGoReadsItsResultsInOrder() throws {
        let hits = try DuckDuckGo().parse(Fixture.fetched("duckduckgo.html", url: "https://html.duckduckgo.com/html/"))
        XCTAssertEqual(hits.count, 10)
        XCTAssertEqual(hits.first?.url, "https://www.swift.org/blog/swift-6.4-released/")
        XCTAssertEqual(hits.map(\.rank), Array(1...10))
        XCTAssertTrue(hits.allSatisfy { !$0.title.isEmpty && $0.engine == "DuckDuckGo" })
        XCTAssertFalse(hits.first?.snippet.isEmpty ?? true)
    }

    func testDuckDuckGoUnwrapsItsRedirectsAndDropsAds() {
        XCTAssertEqual(DuckDuckGo.unwrap("//duckduckgo.com/l/?uddg=https%3A%2F%2Fswift.org%2Fblog%2F&rut=abc"), "https://swift.org/blog/")
        XCTAssertNil(DuckDuckGo.unwrap("https://duckduckgo.com/y.js?ad_domain=example.com"))
        XCTAssertEqual(DuckDuckGo.unwrap("https://swift.org/"), "https://swift.org/")
    }

    func testBraveReadsItsWebResultsOnly() throws {
        let hits = try Brave().parse(Fixture.fetched("brave.html", url: "https://search.brave.com/search?q=swift"))
        XCTAssertGreaterThanOrEqual(hits.count, 10)
        XCTAssertEqual(hits.first?.url, "https://www.swift.org/blog/swift-6.4-released/")
        XCTAssertEqual(hits.first?.title, "Swift 6.4 Released | Swift.org")
        XCTAssertTrue(hits.first?.snippet.contains("WASI") ?? false, hits.first?.snippet ?? "")
        XCTAssertFalse(hits.contains { URL(string: $0.url)?.host?.hasSuffix("brave.com") ?? true })
    }

    func testBingDecodesItsClickThroughLinks() throws {
        let hits = try Bing().parse(Fixture.fetched("bing.html", url: "https://www.bing.com/search?q=swift"))
        XCTAssertEqual(hits.count, 10)
        XCTAssertTrue(hits.allSatisfy { $0.url.hasPrefix("http") && !$0.url.contains("bing.com/ck/") }, "\(hits.map(\.url))")
        XCTAssertEqual(Bing.unwrap("https://www.bing.com/ck/a?!&&p=abc&u=a1aHR0cHM6Ly93d3cuc3dpZnQub3JnLw&ntb=1"), "https://www.swift.org/")
        XCTAssertNil(Bing.unwrap("https://www.bing.com/ck/a?!&&p=abc&ntb=1"))
    }

    func testWikipediaReadsItsSearchAPI() throws {
        let hits = try Wikipedia().parse(Fixture.fetched("wikipedia.json", url: "https://en.wikipedia.org/w/rest.php/v1/search/page", type: "application/json"))
        XCTAssertEqual(hits.first?.url, "https://en.wikipedia.org/wiki/Swift_(programming_language)")
        XCTAssertEqual(hits.first?.title, "Swift (programming language)")
        XCTAssertFalse(hits.first?.snippet.contains("<span") ?? true, "the excerpt's markup is gone")
    }

    func testGoogleIsAskedOnlyWithTheirKey() {
        XCTAssertEqual(SearchEngines.standard(environment: [:]).map(\.name), ["DuckDuckGo", "Brave", "Bing", "Wikipedia"])
        XCTAssertEqual(SearchEngines.standard(environment: ["GOOGLE_CSE_KEY": "k", "GOOGLE_CSE_CX": "c"]).map(\.name),
                       ["Google", "DuckDuckGo", "Brave", "Bing", "Wikipedia"])
        XCTAssertEqual(SearchEngines.standard(environment: ["GOOGLE_CSE_KEY": "k"]).count, 4, "a key without an engine id is no Google")
    }

    func testFusionPutsWhatSeveralEnginesFoundFirst() {
        let a = [Hit(url: "https://one.example/", title: "One", snippet: "", engine: "A", rank: 1),
                 Hit(url: "https://two.example/page?utm_source=x", title: "Two", snippet: "short", engine: "A", rank: 2)]
        let b = [Hit(url: "https://www.two.example/page/", title: "Two", snippet: "a longer snippet", engine: "B", rank: 1),
                 Hit(url: "http://127.0.0.1/admin", title: "Local", snippet: "", engine: "B", rank: 2)]
        let fused = Fusion.fuse([a, b])
        XCTAssertEqual(fused.map { URLNormal.site($0.url) }, ["two.example", "one.example"], "a private address is never a result")
        XCTAssertEqual(fused[0].engines, ["B", "A"], "best rank first")
        XCTAssertEqual(fused[0].snippet, "a longer snippet")
        XCTAssertNil(fused[0].url.query, "tracking parameters are not the page's")
    }
}
