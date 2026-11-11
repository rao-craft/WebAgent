import Foundation
import XCTest
@testable import WebCore

/// What a prompt's links are, and which addresses the crawl may reach.
final class GuardTests: XCTestCase {
    func testLinksAreFoundAsWrittenOrBare() {
        let ask = "$web compare https://www.swift.org/blog/swift-6.4-released/, the forum (forums.swift.org/t/swift-6-4-release-process/85421) "
            + "and https://en.wikipedia.org/wiki/Swift_(programming_language). Also https://www.swift.org/blog/swift-6.4-released/#top again."
        XCTAssertEqual(LinkFinder.links(in: ask).map(\.absoluteString), [
            "https://www.swift.org/blog/swift-6.4-released/",
            "http://forums.swift.org/t/swift-6-4-release-process/85421",
            "https://en.wikipedia.org/wiki/Swift_(programming_language)",
        ])
        XCTAssertEqual(LinkFinder.links(from: ["swift.org/blog", " ", "https://swift.org/blog?utm_source=x&page=2"]).map(\.absoluteString),
                       ["https://swift.org/blog", "https://swift.org/blog?page=2"])
    }

    func testTheQueryIsTheAskWithoutItsLinksAndTags() {
        XCTAssertEqual(LinkFinder.query(from: "$web what changed in Swift 6.4? see https://www.swift.org/blog/ #canvas"),
                       "what changed in Swift 6.4? see")
        XCTAssertEqual(LinkFinder.query(from: "https://example.com"), "")
    }

    func testOnePagePerSpelling() {
        let a = URLNormal.normalized(URL(string: "HTTPS://WWW.Swift.org:443/blog/#news")!)!
        let b = URLNormal.normalized(URL(string: "https://swift.org/blog")!)!
        XCTAssertEqual(URLNormal.key(a), URLNormal.key(b))
        XCTAssertEqual(URLNormal.site(a), "swift.org")
        XCTAssertNil(a.fragment)
    }

    func testOnlyPublicHostsOverHTTP() {
        for refused in ["http://127.0.0.1/", "http://10.0.0.2/", "http://192.168.1.1/", "http://172.20.0.1/", "http://169.254.169.254/latest",
                        "http://[::1]/", "http://[fd00::1]/", "http://localhost:3000/", "http://printer.local/", "http://intranet/",
                        "file:///etc/hosts", "ftp://example.com/", "http://100.64.0.1/", "http://0.0.0.0/"] {
            XCTAssertNotEqual(HostGuard.check(URL(string: refused)!), .allowed, refused)
        }
        for allowed in ["https://swift.org/", "http://8.8.8.8/", "https://[2606:4700::1111]/", "https://en.wikipedia.org/wiki/Swift"] {
            XCTAssertEqual(HostGuard.check(URL(string: allowed)!), .allowed, allowed)
        }
    }

    func testRobotsReadsItsOwnGroupThenEveryones() throws {
        let forums = Robots(parsing: String(decoding: try Fixture.data("forums-robots.txt"), as: UTF8.self))
        XCTAssertTrue(forums.allows(URL(string: "https://forums.swift.org/t/swift-6-4-release-process/85421")!))

        let closed = Robots(parsing: "User-agent: *\nAllow: /\n\nUser-agent: WebAgent\nDisallow: /\n")
        XCTAssertFalse(closed.allows(URL(string: "https://example.com/page")!), "its own group, not everyone's")

        let rules = Robots(parsing: """
            User-agent: *
            Disallow: /private
            Allow: /private/open
            Disallow: /*.pdf$
            Disallow: /search?
            """)
        XCTAssertFalse(rules.allows(URL(string: "https://example.com/private/notes")!))
        XCTAssertTrue(rules.allows(URL(string: "https://example.com/private/open/notes")!), "the longest rule decides")
        XCTAssertFalse(rules.allows(URL(string: "https://example.com/files/a.pdf")!))
        XCTAssertTrue(rules.allows(URL(string: "https://example.com/files/a.pdf.html")!), "$ anchors the end")
        XCTAssertFalse(rules.allows(URL(string: "https://example.com/search?q=x")!))
        XCTAssertTrue(rules.allows(URL(string: "https://example.com/")!))
        XCTAssertFalse(Robots.shut.allows(URL(string: "https://example.com/")!))
    }
}
