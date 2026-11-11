import Foundation
import XCTest
@testable import WebCore

/// A page's words as a reader sees them, and the sentences nearest a request.
final class ReadTests: XCTestCase {
    func testAnArticleIsItsWordsWithoutTheChrome() throws {
        let url = URL(string: "https://www.swift.org/blog/swift-6.4-released/")!
        let page = Readable(html: String(decoding: try Fixture.data("swift-blog.html"), as: UTF8.self), url: url)
        XCTAssertTrue(page.title.contains("Swift 6.4"), page.title)
        XCTAssertTrue(page.text.contains("Swift 6.4"))
        XCTAssertFalse(page.scripted)
        XCTAssertGreaterThan(page.text.count, 2_000)
        XCTAssertFalse(page.text.contains("function("), "no script reaches the text")
        XCTAssertTrue(page.links.allSatisfy { URLNormal.site($0) == "swift.org" }, "same-site links only")
    }

    func testAScriptBuiltPageIsKnownAsOne() throws {
        let url = URL(string: "https://docs.swift.org/latest/documentation/packagemanagerdocs/6.4/")!
        let page = Readable(html: String(decoding: try Fixture.data("swiftpm-docs.html"), as: UTF8.self), url: url)
        XCTAssertTrue(page.scripted, "a documentation shell: its words come from scripts")
    }

    func testBlocksNeverRunTogether() {
        let html = "<html><body><nav>Home About</nav><main><h1>Title</h1><p>First paragraph is here and long enough.</p><ul><li>One item</li></ul>"
            + "<p>" + String(repeating: "More words follow. ", count: 20) + "</p></main><footer>© Footer</footer></body></html>"
        let page = Readable(html: html, url: URL(string: "https://example.com/")!)
        XCTAssertTrue(page.text.hasPrefix("## Title\nFirst paragraph is here and long enough.\nOne item"), page.text)
        XCTAssertFalse(page.text.contains("Footer"))
        XCTAssertFalse(page.text.contains("About"))
    }

    func testTheNearestSentencesAreTheFacts() throws {
        let url = URL(string: "https://www.swift.org/blog/swift-6.4-released/")!
        let text = Readable(html: String(decoding: try Fixture.data("swift-blog.html"), as: UTF8.self), url: url).text
        let terms = Distiller.terms("what changed in Swift 6.4 testing")
        XCTAssertEqual(terms, ["changed", "swift", "6.4", "testing"])
        let facts = Distiller.extract(text, terms: terms)
        XCTAssertEqual(facts.count, 3)
        XCTAssertTrue(facts.allSatisfy { $0.fact == $0.quote && Distiller.quoted($0.quote, in: text) })
        XCTAssertTrue(facts.allSatisfy { $0.fact.lowercased().contains("swift") })
        let excerpt = Distiller.excerpt(text, terms: terms, limit: 500)
        XCTAssertLessThanOrEqual(excerpt.count, 520)
        XCTAssertTrue(excerpt.contains("6.4"))
    }

    func testAQuoteIsThePagesOwnWords() {
        let text = "Swift 6.4 is now available.\nIt brings   “typed throws” to   more places."
        XCTAssertTrue(Distiller.quoted("it brings \"typed throws\" to more places", in: text))
        XCTAssertFalse(Distiller.quoted("Swift 6.4 adds a garbage collector", in: text))
        XCTAssertFalse(Distiller.quoted("Swift", in: text), "too short to say anything")
    }
}
