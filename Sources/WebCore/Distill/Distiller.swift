import Foundation
import NaturalLanguage

/// A page as a model reads it for facts: its number, where it is, and its words nearest the request.
public struct PageExcerpt: Sendable, Equatable {
    public var n: Int
    public var site: String
    public var title: String
    public var text: String
}

/// A model that reads excerpts for the facts a request needs: the host's, in the agent.
public protocol FactModel: Sendable {
    /// Facts by the source number they came from.
    func facts(ask: String, excerpts: [PageExcerpt]) async throws -> [Int: [Fact]]
}

/// The words a request turns on, and the sentences of a page nearest them.
public enum Distiller {
    static let stopwords: Set<String> = [
        "the", "and", "for", "are", "but", "not", "you", "all", "any", "can", "had", "her", "was", "one", "our", "out", "has", "have",
        "what", "when", "where", "which", "who", "why", "how", "with", "this", "that", "these", "those", "from", "into", "about", "does",
        "did", "its", "it's", "is", "be", "of", "to", "in", "on", "a", "an", "or", "as", "at", "by", "me", "my", "do", "tell", "find",
        "show", "give", "please", "use", "using", "web", "search", "look", "up", "latest", "new", "get", "there", "their", "they",
        "them", "then", "than", "will", "would", "should", "could", "also", "just", "some", "more", "most", "other", "your", "yours",
    ]

    /// The request's own words, lowercased, without the ones every sentence has.
    public static func terms(_ text: String) -> [String] {
        var seen = Set<String>()
        return words(text).filter { $0.count >= 2 && !stopwords.contains($0) && seen.insert($0).inserted }
    }

    /// A text's words, lowercased, versions kept whole (`6.4`, `c++`).
    static func words(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber && $0 != "." && $0 != "+" && $0 != "#" }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            .filter { !$0.isEmpty }
    }

    /// The page's sentences, in order.
    static func sentences(_ text: String, headings: Bool = true) -> [String] {
        var found: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("## "), !headings { continue }
            let line = String(line).replacingOccurrences(of: "## ", with: "")
            let tokenizer = NLTokenizer(unit: .sentence)
            tokenizer.string = line
            tokenizer.enumerateTokens(in: line.startIndex..<line.endIndex) { range, _ in
                let sentence = line[range].trimmingCharacters(in: .whitespacesAndNewlines)
                if sentence.count >= 25 { found.append(sentence) }
                return true
            }
        }
        return found
    }

    /// How many of the request's words a sentence has, and whether it carries a number.
    static func score(_ sentence: String, terms: [String]) -> Double {
        let words = Set(words(sentence))
        let hits = terms.filter { words.contains($0) }.count
        guard hits > 0 else { return 0 }
        return Double(hits) + (sentence.contains(where: \.isNumber) ? 0.25 : 0) - (sentence.count > 400 ? 0.5 : 0)
    }

    /// The sentences nearest the request, in the page's own order, up to `limit` characters; the page's opening
    /// when none is near.
    public static func excerpt(_ text: String, terms: [String], limit: Int) -> String {
        let all = sentences(text)
        guard !all.isEmpty else { return String(text.prefix(limit)) }
        let ranked = rank(all, terms: terms, atLeast: 0.01)
        var chosen: [Int] = []
        var used = 0
        for index in ranked {
            let length = all[index].count + 1
            if used + length > limit { continue }
            chosen.append(index); used += length
        }
        if chosen.isEmpty {
            var opening = ""
            for sentence in all where opening.count + sentence.count + 1 <= limit { opening += (opening.isEmpty ? "" : " ") + sentence }
            return opening.isEmpty ? String(all[0].prefix(limit)) : opening
        }
        return chosen.sorted().map { all[$0] }.joined(separator: " … ")
    }

    /// Without a model: the page's `count` sentences nearest the request, each its own quote.
    public static func extract(_ text: String, terms: [String], count: Int = 3) -> [Fact] {
        // Headings name things; facts say them. A run of capitalised link words (a menu, a list of posts) is no fact either.
        var seen = Set<String>()
        let all = sentences(text, headings: false).filter { sentence in
            let words = sentence.split(separator: " ")
            let capitalised = words.filter { $0.first?.isUppercase == true }.count
            return words.count >= 6 && Double(capitalised) / Double(words.count) < 0.6 && seen.insert(sentence.lowercased()).inserted
        }
        let chosen = rank(all, terms: terms, atLeast: 1).prefix(count).sorted()
        return chosen.map { index -> Fact in
            let sentence = String(all[index].prefix(320))
            return Fact(fact: sentence, quote: sentence)
        }
    }

    /// The indices of the sentences scoring at least `floor`, best first; ties keep the page's order.
    static func rank(_ sentences: [String], terms: [String], atLeast floor: Double) -> [Int] {
        var scored: [(index: Int, score: Double)] = []
        for (index, sentence) in sentences.enumerated() {
            let value = score(sentence, terms: terms)
            if value >= floor { scored.append((index, value)) }
        }
        scored.sort { (a: (index: Int, score: Double), b: (index: Int, score: Double)) -> Bool in
            a.score != b.score ? a.score > b.score : a.index < b.index
        }
        return scored.map { $0.index }
    }

    /// Whether a model's quote is the page's: its words, in order, ignoring case, spacing and quote marks.
    public static func quoted(_ quote: String, in text: String) -> Bool {
        let flat = { (s: String) in
            s.lowercased().replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "“", with: "\"")
                .replacingOccurrences(of: "”", with: "\"").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        let needle = flat(quote).trimmingCharacters(in: CharacterSet(charactersIn: " .…\"'"))
        guard needle.count >= 8 else { return false }
        return flat(text).contains(needle)
    }
}
