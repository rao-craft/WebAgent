import Foundation
import GraniteAgents
import WebCore
import XCTest
@testable import WebAgent

/// The package as an app finds it: by its record, with the schema a model is shown and the guide a host prompts with.
final class WebAgentTests: XCTestCase {
    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/web", isDirectory: true)

    override class func setUp() {
        super.setUp()
        // A call through the roster reads the web from the environment: recorded answers, never the live web.
        setenv(RecordedFetcher.variable, fixtures.path, 1)
        unsetenv(SearchEngines.googleKey)
    }

    func testTheRecordIsFoundWithNothingListed() throws {
        let web = try XCTUnwrap(GraniteRoster.discovered().package("web"), "the record is in this test binary")
        XCTAssertEqual(web.module, "WebAgent")
        XCTAssertEqual(web.summary, WebAgent.summary)
        XCTAssertEqual(web.lanes, 2)
        XCTAssertTrue(web.makes.isEmpty, "it writes no file")
    }

    func testTheSchemaIsWhatAModelIsShown() {
        let web = AnyAgentPackage(WebAgent.self)
        XCTAssertEqual(web.schema, .object([
            .init(name: "query", schema: .string, required: false),
            .init(name: "urls", schema: .array(.string), required: false),
            .init(name: "search", schema: .boolean, required: false),
            .init(name: "depth", schema: .integer, required: false),
            .init(name: "pages", schema: .integer, required: false),
        ]))
        XCTAssertFalse(web.takesDirectory, "no folder: nothing is written")
        XCTAssertEqual(Set(web.fields.keys), ["query", "urls", "search", "depth", "pages"], "a note beside every field the model sees")
    }

    func testTheGuideSaysHowToCiteAndAccount() {
        let guide = AnyAgentPackage(WebAgent.self).guide
        for words in ["DuckDuckGo, Brave, Bing and Wikipedia", "(found on <site>)", "(found on swift.org)", "never invent one",
                      "\"Web work\" section", "`query`", "`search: false`", "`depth: 1`", "robots.txt", "writes no file", "Before answering".lowercased(),
                      "never an address you made up", "never call again with the same link"] {
            XCTAssertTrue(guide.lowercased().contains(words.lowercased()), "the guide says \(words)")
        }
    }

    /// The call as a host makes it: JSON in, the person's ask beside it, JSON out with the sources and the work.
    func testACallThroughTheRosterAnswersWithSourcesAndWork() async throws {
        let notes = Lines()
        let input = try JSONSerialization.data(withJSONObject: ["query": "swift 6.4 release", "pages": 3])
        let answer = try await AnyAgentPackage(WebAgent.self).perform(input, host: AgentHost(
            ask: "what changed in Swift 6.4? https://www.swift.org/blog/swift-6.4-released/", note: notes.say))
        let result = try JSONDecoder().decode(WebResult.self, from: answer)
        XCTAssertEqual(result.query, "swift 6.4 release", "the model's search, not the ask's words")
        XCTAssertEqual(result.paths, [])
        XCTAssertEqual(result.sources.first?.via, .prompt, "the person's link first")
        XCTAssertEqual(result.sources.first?.url, "https://www.swift.org/blog/swift-6.4-released/")
        XCTAssertEqual(result.sources.count, 3)
        XCTAssertEqual(result.work.linked, ["https://www.swift.org/blog/swift-6.4-released/"])
        XCTAssertEqual(result.work.searched.count, 4)
        XCTAssertTrue(result.notes.contains { $0.contains("(found on swift.org)") })
        XCTAssertLessThan(answer.count, WebResult.limit + 200)
        XCTAssertFalse(notes.all.isEmpty, "the host is told as it goes")
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: answer) as? [String: Any])
        XCTAssertEqual(object["format"] as? String, AgentAnswerStandard.format, "granite-answer/1, stamped by the runner")
        XCTAssertEqual((object["agent"] as? [String: Any])?["word"] as? String, "web")
        for key in ["sources", "work", "notes", "problems", "paths"] { XCTAssertNotNil(object[key], key) }
    }

    func testARefusalSaysWhetherToFixTheCallOrWait() async throws {
        do {
            _ = try await AnyAgentPackage(WebAgent.self).perform(Data("{}".utf8), host: AgentHost())
            XCTFail("nothing to look up")
        } catch {
            XCTAssertEqual(AgentRefusal.of(error)?.kind, .call, "\(error)")
        }
        XCTAssertEqual(WebError.unreachable("offline").refusal.kind, .reach)
        XCTAssertEqual(WebError.enginesDown("Brave answered 429").refusal.kind, .reach)
        XCTAssertEqual(WebError.unreadable("https://github.com/a/b answered 404").refusal.kind, .call, "a gone link is the call's to fix, never try-later")
    }

    func testABigAnswerIsFittedNotCut() throws {
        var work = WebWork()
        work.searched = [.init(engine: "DuckDuckGo", query: "q", hits: 10, ms: 10, error: nil)]
        let long = String(repeating: "A sentence about Swift 6.4 that is quite long. ", count: 20)
        let sources = (1...12).map { n in
            Source(n: n, title: "Page \(n)", url: "https://example.com/\(n)", site: "example.com", via: .search, engines: ["DuckDuckGo"],
                   published: nil, rendered: false, excerpt: long,
                   facts: Array(repeating: Fact(fact: String(long.prefix(300)), quote: String(long.prefix(300))), count: 6))
        }
        let result = WebResult(WebOutcome(query: "q", sources: sources, work: work, notes: [], problems: [])).fitted(to: 12_000)
        XCTAssertLessThanOrEqual(result.size, 12_000)
        XCTAssertTrue(result.problems.contains { $0.kind == "trim" })
        XCTAssertEqual(result.sources.first?.n, 1, "the first pages are kept")
    }
}

final class Lines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    var all: [String] { lock.withLock { lines } }
    var say: @Sendable (String) -> Void { { [weak self] line in self?.lock.withLock { self?.lines.append(line) } } }
}
