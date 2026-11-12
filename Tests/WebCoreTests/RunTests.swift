import Foundation
import XCTest
@testable import WebCore

/// The whole run on the recorded web: engines, fusion, the crawl, the facts, the notes.
final class RunTests: XCTestCase {
    func run(_ request: WebRequest, model: (any FactModel)? = nil, notes: Notes = Notes()) async throws -> WebOutcome {
        try await WebRun(engines: SearchEngines.standard(environment: [:]), fetcher: Fixture.recorded(), renderer: NoRenderer(),
                         model: model, note: notes.say).run(request)
    }

    func testASearchReadsTheBestResultsAndSaysWhatItDid() async throws {
        let notes = Notes()
        let outcome = try await run(WebRequest(ask: "$web what changed in Swift 6.4", pages: 3), notes: notes)
        XCTAssertEqual(outcome.query, "what changed in Swift 6.4")
        XCTAssertEqual(outcome.work.searched.map(\.engine), ["DuckDuckGo", "Brave", "Bing", "Wikipedia"])
        XCTAssertEqual(outcome.work.results, 45)
        XCTAssertEqual(outcome.sources.map(\.site), ["swift.org", "forums.swift.org", "avanderlee.com"])
        XCTAssertTrue(outcome.work.skipped.contains { $0.url.hasPrefix("https://docs.swift.org/") && $0.why == "no readable text" },
                      "a page its scripts write, with no browser to draw it, has nothing to read")
        XCTAssertEqual(outcome.sources.map(\.n), [1, 2, 3])
        XCTAssertTrue(outcome.sources.allSatisfy { $0.via == .search && !$0.engines.isEmpty })
        XCTAssertFalse(outcome.sources[0].facts.isEmpty)
        XCTAssertEqual(outcome.work.distilled, "extract")
        XCTAssertTrue(outcome.work.skipped.contains { $0.url == "https://developer.apple.com/swift/whats-new/" && $0.why == "robots.txt asks not to" },
                      "a server error on robots.txt closes the site, as RFC 9309 says")
        XCTAssertTrue(outcome.work.skipped.contains { $0.url == "https://www.swift.com/" && $0.why == "robots.txt asks not to" })
        XCTAssertTrue(outcome.notes.contains { $0.hasPrefix("Searched DuckDuckGo, Brave, Bing and Wikipedia for “what changed in Swift 6.4”: 45 results") },
                      "\(outcome.notes)")
        XCTAssertTrue(outcome.notes.contains { $0.contains("(found on <site>), e.g. (found on swift.org)") })
        XCTAssertTrue(outcome.notes.contains { $0.contains("“Web work” section") })
        XCTAssertTrue(notes.all.contains("45 results, 37 distinct pages"), "\(notes.all)")
        XCTAssertTrue(notes.all.contains { $0.hasPrefix("Read 1/3: ") })
    }

    func testThePersonsLinksComeFirstAndAreReadAsAsked() async throws {
        // swift.com's robots.txt closes it to the agent; the person linked it, so it is read.
        let outcome = try await run(WebRequest(ask: "summarize https://www.swift.com/ and https://www.swift.org/blog/swift-6.4-released/",
                                               search: false))
        XCTAssertNil(outcome.query)
        XCTAssertTrue(outcome.work.searched.isEmpty)
        XCTAssertEqual(outcome.work.linked, ["https://www.swift.com/", "https://www.swift.org/blog/swift-6.4-released/"])
        XCTAssertEqual(outcome.sources.map(\.url), ["https://www.swift.com/", "https://www.swift.org/blog/swift-6.4-released/"])
        XCTAssertTrue(outcome.sources.allSatisfy { $0.via == .prompt && $0.engines.isEmpty })
        XCTAssertTrue(outcome.notes.contains { $0.hasPrefix("Read 2 links in the prompt directly") })
    }

    func testAModelsFactIsKeptOnlyWhenItQuotesThePage() async throws {
        let model = ScriptedModel([
            1: [Fact(fact: "Swift 6.4 is out.", quote: "Swift 6.4 is now available."),
                Fact(fact: "Swift 6.4 adds a garbage collector.", quote: "Swift 6.4 adds a tracing garbage collector to the runtime")],
            9: [Fact(fact: "A page that was never read.", quote: "nothing at all here to see")],
        ])
        let outcome = try await run(WebRequest(urls: ["https://www.swift.org/blog/swift-6.4-released/"], search: false), model: model)
        XCTAssertEqual(outcome.work.distilled, "model")
        XCTAssertEqual(outcome.sources[0].facts, [Fact(fact: "Swift 6.4 is out.", quote: "Swift 6.4 is now available.")])
        XCTAssertEqual(model.asked.map(\.n), [1])
        XCTAssertLessThanOrEqual(model.asked[0].text.count, 2_500)
        XCTAssertTrue(outcome.problems.contains { $0.kind == "model" && $0.text.hasPrefix("1 fact the model gave did not quote its page") },
                      "\(outcome.problems)")
    }

    func testNothingToLookUpIsRefused() async throws {
        do {
            _ = try await run(WebRequest(ask: "$web", search: true))
            XCTFail("no words and no link")
        } catch let error as WebError {
            XCTAssertEqual(error, .nothingAsked)
        }
    }

    func testAnEngineThatFailsIsAProblemNotTheEnd() async throws {
        struct Down: SearchEngine {
            let name = "Down"
            func request(for query: String) -> FetchRequest { FetchRequest(url: URL(string: "https://down.example/search")!) }
            func parse(_ fetched: Fetched) throws -> [Hit] { [] }
        }
        let outcome = try await WebRun(engines: [Down(), DuckDuckGo()], fetcher: Fixture.recorded(), renderer: NoRenderer())
            .run(WebRequest(query: "swift 6.4 release", pages: 1))
        XCTAssertEqual(outcome.sources.count, 1)
        XCTAssertEqual(outcome.work.searched.first?.error, "not recorded")
        XCTAssertTrue(outcome.problems.contains { $0.kind == "engine" && $0.text.hasPrefix("Down gave nothing") })
    }

    func testEveryEngineOutOfReachIsTryLater() async throws {
        struct Offline: Fetching {
            func fetch(_ request: FetchRequest) async throws -> Fetched { throw FetchError.unreachable("offline") }
            var resolvesHosts: Bool { false }
        }
        do {
            _ = try await WebRun(engines: SearchEngines.standard(environment: [:]), fetcher: Offline(), renderer: NoRenderer())
                .run(WebRequest(query: "swift"))
            XCTFail("nothing answered")
        } catch let error as WebError {
            guard case .unreachable = error else { return XCTFail("\(error)") }
        }
        do {
            _ = try await WebRun(engines: SearchEngines.standard(environment: [:]), fetcher: Offline(), renderer: NoRenderer())
                .run(WebRequest(urls: ["https://www.swift.org/blog/"], search: false))
            XCTFail("nothing answered")
        } catch let error as WebError {
            guard case .unreachable = error else { return XCTFail("a link the network could not reach is try-later: \(error)") }
        }
    }

    func testEnginesThatAnswerWithoutResultsAreNotAnOfflineMac() async throws {
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("web-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: empty.appendingPathComponent("index.json"))
        do {
            _ = try await WebRun(engines: SearchEngines.standard(environment: [:]), fetcher: RecordedFetcher(folder: empty), renderer: NoRenderer())
                .run(WebRequest(query: "swift"))
            XCTFail("no engine gave results")
        } catch let error as WebError {
            guard case .enginesDown = error else { return XCTFail("\(error)") }
            XCTAssertFalse(error.description.contains("offline"), error.description)
        }
    }

    /// The call that looped in Craft on 2026-11-12: a made-up GitHub link, `search: false`, a query beside it.
    func testALinkThatIsGoneFallsBackToTheSearch() async throws {
        let notes = Notes()
        let outcome = try await run(WebRequest(query: "swift 6.4 release", urls: ["https://github.com/CosmosMuseum/cosmos-meteor-shower"],
                                               search: false, pages: 2), notes: notes)
        XCTAssertEqual(outcome.query, "swift 6.4 release")
        XCTAssertEqual(outcome.sources.map(\.site), ["swift.org", "forums.swift.org"])
        XCTAssertTrue(outcome.sources.allSatisfy { $0.via == .search })
        XCTAssertTrue(outcome.work.skipped.contains { $0.url == "https://github.com/CosmosMuseum/cosmos-meteor-shower" && $0.why == "answered 404" })
        XCTAssertEqual(outcome.notes.first, "The link could not be read (https://github.com/CosmosMuseum/cosmos-meteor-shower answered 404), "
                       + "so the engines were searched for “swift 6.4 release” instead.")
        XCTAssertFalse(outcome.notes.contains { $0.hasPrefix("Read the link in the prompt") }, "it was not read: \(outcome.notes)")
        XCTAssertTrue(notes.all.contains { $0.contains("searching for “swift 6.4 release” instead") }, "\(notes.all)")
    }

    func testALinkThatIsGoneWithNothingToSearchIsTheCallsToFix() async throws {
        do {
            _ = try await run(WebRequest(urls: ["https://github.com/CosmosMuseum/cosmos-meteor-shower"], search: false))
            XCTFail("a 404 and nothing to search for")
        } catch let error as WebError {
            guard case .unreadable = error else { return XCTFail("a page that answered is not an offline web: \(error)") }
            XCTAssertTrue(error.description.contains("answered 404: no such page, or a private one"), error.description)
            XCTAssertTrue(error.description.contains("Do not call web again with the same link"), error.description)
        }
    }
}
