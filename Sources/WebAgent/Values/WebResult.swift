import Foundation
import GraniteAgents
import WebCore

/// What a call answers: the pages it read, numbered, each with its facts; the work it did; how to use them. No file.
public struct WebResult: AgentAnswer, Equatable {
    /// No file is written: the answer is the work.
    public var paths: [String] = []
    /// The search the engines were given; nil when only links were read.
    public var query: String?
    /// The pages read, numbered: the person's links first, then the results in their fused order.
    public var sources: [Source]
    /// What the agent did, step by step: the engines, the crawl, what it skipped, how the facts were found.
    public var work: WebWork
    /// One sentence each: what was done, then how to credit the sources and account for the work.
    public var notes: [String]
    public var made: [AgentMade] = []
    public var expected: [AgentExpected] = []
    /// What the call could only do in part: an engine that gave nothing, a model that could not read, a trim.
    public var problems: [AgentProblem] = []
    public var payloads: [AgentPayload] = []

    public init(_ outcome: WebOutcome) {
        query = outcome.query
        sources = outcome.sources
        work = outcome.work
        notes = outcome.notes
        problems = outcome.problems.map { AgentProblem(kind: $0.kind, text: $0.text) }
    }

    /// Craft passes a tool's answer on up to 30,000 characters; the answer keeps well under it, so nothing is cut
    /// mid-word. Excerpts shorten first, then each page keeps fewer facts, then the last pages go, said in `problems`.
    public static let limit = 20_000

    public func fitted(to limit: Int = WebResult.limit) -> WebResult {
        var result = self
        guard result.size > limit else { return result }
        for length in [400, 200, 0] {
            for index in result.sources.indices { result.sources[index].excerpt = Self.shortened(result.sources[index].excerpt, to: length) }
            if result.size <= limit { return result.noting("Excerpts were shortened to fit the answer.") }
        }
        for count in [4, 2] {
            for index in result.sources.indices { result.sources[index].facts = Array(result.sources[index].facts.prefix(count)) }
            if result.size <= limit { return result.noting("Each page keeps its first \(count) facts to fit the answer.") }
        }
        let before = result.sources.count
        while result.size > limit, result.sources.count > 1 { result.sources.removeLast() }
        return result.noting("The last \(before - result.sources.count) pages were left out to fit the answer.")
    }

    var size: Int { (try? JSONEncoder().encode(self).count) ?? 0 }

    func noting(_ text: String) -> WebResult {
        var result = self
        result.problems.append(AgentProblem(kind: "trim", text: text))
        return result
    }

    static func shortened(_ text: String, to length: Int) -> String {
        guard text.count > length else { return text }
        guard length > 0 else { return "" }
        let cut = text.prefix(length)
        return (cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? String(cut)) + "…"
    }
}
