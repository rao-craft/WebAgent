import Foundation
import GraniteAgents
import WebCore
import XCTest
@testable import WebAgent

/// The package installed as Craft installs it (Granite's `AgentInstaller`: a runner of one executable, built in
/// release) and called over the wire in a process of its own. Gated (`WEB_BUILD=1`): a build takes a minute.
final class WebBuildTests: XCTestCase {
    func testTheInstalledRunnerAnswersOverTheWire() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["WEB_BUILD"] == "1", "set WEB_BUILD=1 to install and run the agent")
        let package = WebAgentTests.fixtures.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let shelf = try Self.folder()
        // A copy, as Craft installs from a clone: `swift test` holds this package's own folder, and the installer's
        // `swift package dump-package` there would wait on it for good.
        let source = try Self.folder().appendingPathComponent("WebAgent")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        for item in ["Package.swift", "Package.resolved", "Sources", "Tests"] {
            try FileManager.default.copyItem(at: package.appendingPathComponent(item), to: source.appendingPathComponent(item))
        }
        let installation = try await AgentInstaller(folder: shelf).install(.path(source.path))
        XCTAssertEqual(installation.name, "WebAgent")
        let executable = AgentShelf(folder: shelf).executable(of: installation)

        let entries = try await AgentProcess(executable: executable).describe()
        XCTAssertEqual(entries.map(\.word), ["web"])

        var environment = ProcessInfo.processInfo.environment
        environment[RecordedFetcher.variable] = WebAgentTests.fixtures.path
        let input = try JSONSerialization.data(withJSONObject: ["urls": ["https://www.swift.org/blog/swift-6.4-released/"], "search": false])
        let answer = try await AgentProcess(executable: executable, environment: environment)
            .perform(word: "web", input: input, host: AgentHost(ask: "what is new in Swift 6.4"))
        let result = try JSONDecoder().decode(WebResult.self, from: answer)
        XCTAssertEqual(result.sources.map(\.site), ["swift.org"])
        XCTAssertFalse(result.sources[0].facts.isEmpty)
    }

    static func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("web-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
