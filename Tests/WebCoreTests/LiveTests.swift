import Foundation
import XCTest
@testable import WebCore

/// The live web, once: every engine asked, pages read, one drawn in WebKit. Gated (`WEB_LIVE=1`): it needs the network
/// and the engines' good will.
final class LiveTests: XCTestCase {
    func testTheLiveWebAnswers() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["WEB_LIVE"] == "1", "set WEB_LIVE=1 to search and crawl the live web")
        let outcome = try await WebRun().run(WebRequest(ask: "what changed in Swift 6.4 https://www.swift.org/blog/swift-6.4-released/", pages: 4))
        XCTAssertGreaterThanOrEqual(outcome.work.searched.filter { $0.hits > 0 }.count, 2, "\(outcome.work.searched)")
        XCTAssertEqual(outcome.sources.first?.site, "swift.org")
        XCTAssertEqual(outcome.sources.first?.via, .prompt)
        XCTAssertGreaterThanOrEqual(outcome.sources.count, 3)
    }

    func testWebKitDrawsAScriptBuiltPage() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["WEB_LIVE"] == "1", "set WEB_LIVE=1 to draw a live page")
        let drawn = try await WebKitRenderer().render(URL(string: "https://docs.swift.org/latest/documentation/packagemanagerdocs/6.4/")!, timeout: 20)
        let page = Readable(html: drawn.html, url: drawn.url)
        XCTAssertGreaterThan(page.text.count, 400, "the scripts wrote the page")
        XCTAssertTrue(page.text.contains("Swift Build"))
    }
}
