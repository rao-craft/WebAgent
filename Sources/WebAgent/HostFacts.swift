import Foundation
import GraniteAgents
import WebCore

/// The host's model, reading the pages for the facts a request needs: each fact with its page's number and the
/// page's own words that say it. A fact whose quote is not the page's is dropped by the run, never kept.
struct HostFacts: FactModel {
    let model: any AgentHostModel

    struct Answer: Decodable {
        struct Item: Decodable {
            var source: Int
            var fact: String
            var quote: String
        }
        var facts: [Item]
    }

    static let system = """
        You read web pages for the facts a person's request needs. Use only the pages' text, never what you know. \
        Each fact is one plain sentence, names its page by number in `source`, and carries in `quote` the exact words \
        from that page that say it (copied, not paraphrased, at most 40 words). Prefer facts with numbers, names, \
        versions and dates. Give at most 6 facts per page and 24 in all; leave out pages with nothing relevant. When \
        pages disagree, give both facts.
        """

    func facts(ask: String, excerpts: [PageExcerpt]) async throws -> [Int: [Fact]] {
        let pages = excerpts.map { "[\($0.n)] \($0.title) (\($0.site))\n\($0.text)" }.joined(separator: "\n\n")
        let user = "Request: \(ask)\n\nPages:\n\n\(pages)"
        let answer = try await model.object(Answer.self, notes: [
            "source": "the page's number, as [n] gives it",
            "fact": "one sentence the request needs",
            "quote": "the page's exact words that say it",
        ], system: Self.system, user: user, maxTokens: 2_500, seconds: 120)
        var found: [Int: [Fact]] = [:]
        for item in answer.facts { found[item.source, default: []].append(Fact(fact: item.fact, quote: item.quote)) }
        return found
    }
}
