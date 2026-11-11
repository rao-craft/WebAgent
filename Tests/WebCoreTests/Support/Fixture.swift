import Foundation
@testable import WebCore

enum Fixture {
    /// Engines' answers and pages recorded on 2026-11-11 for "swift 6.4 release" (never the live web).
    static let web = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Fixtures/web", isDirectory: true)

    static func data(_ name: String) throws -> Data { try Data(contentsOf: web.appendingPathComponent(name)) }

    static func fetched(_ name: String, url: String, type: String = "text/html") throws -> Fetched {
        Fetched(url: URL(string: url)!, status: 200, mimeType: type, encoding: "utf-8", data: try data(name))
    }

    static func recorded() throws -> RecordedFetcher { try RecordedFetcher(folder: web) }
}

/// A model that answers what it is told to, counting its calls.
final class ScriptedModel: FactModel, @unchecked Sendable {
    let answer: [Int: [Fact]]
    private(set) var asked: [PageExcerpt] = []
    init(_ answer: [Int: [Fact]]) { self.answer = answer }
    func facts(ask: String, excerpts: [PageExcerpt]) async throws -> [Int: [Fact]] {
        asked = excerpts
        return answer
    }
}

/// Notes said during a run, in order.
final class Notes: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    var all: [String] { lock.withLock { lines } }
    var say: @Sendable (String) -> Void { { [weak self] line in self?.lock.withLock { self?.lines.append(line) } } }
}
