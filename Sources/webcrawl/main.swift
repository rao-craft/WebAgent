// webcrawl: the web agent's run from a terminal, with no host and no model (the nearest sentences are kept).
//
//   webcrawl what changed in swift 6.4 https://www.swift.org/blog/
//   webcrawl --query "swift 6.4 release" --pages 4
//   webcrawl --no-search --depth 1 https://www.swift.org/blog/
//   webcrawl --json …                 the sources and work as JSON
//
// WEB_FIXTURES_DIR reads a recorded web instead of the live one.

import Foundation
import WebCore

var words: [String] = []
var request = WebRequest()
var json = false
var arguments = CommandLine.arguments.dropFirst()[...]
while let argument = arguments.popFirst() {
    switch argument {
    case "--query": request.query = arguments.popFirst()
    case "--pages": request.pages = arguments.popFirst().flatMap(Int.init) ?? 6
    case "--depth": request.depth = arguments.popFirst().flatMap(Int.init) ?? 0
    case "--no-search": request.search = false
    case "--json": json = true
    case "-h", "--help":
        print("usage: webcrawl [--query Q] [--pages N] [--depth 0|1] [--no-search] [--json] <words and links…>")
        exit(0)
    default: words.append(argument)
    }
}
request.ask = words.isEmpty ? nil : words.joined(separator: " ")

let recorded = RecordedFetcher.fromEnvironment()
let web = WebRun(fetcher: recorded ?? IsolatedFetcher(), renderer: recorded == nil ? WebKitRenderer() : NoRenderer(),
                 note: { line in FileHandle.standardError.write(Data("· \(line)\n".utf8)) })
do {
    let outcome = try await web.run(request)
    if json {
        struct Printed: Encodable { var query: String?; var sources: [Source]; var work: WebWork; var notes: [String] }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(Printed(query: outcome.query, sources: outcome.sources, work: outcome.work, notes: outcome.notes))
        print(String(decoding: data, as: UTF8.self))
    } else {
        for source in outcome.sources {
            let found = source.engines.isEmpty ? source.via.rawValue : source.engines.joined(separator: ", ")
            print("[\(source.n)] \(source.title)\n    \(source.url)  (found on \(source.site); \(found)\(source.rendered ? "; WebKit" : ""))")
            for fact in source.facts { print("    • \(fact.fact)") }
        }
        print("")
        for note in outcome.notes { print(note) }
        for problem in outcome.problems { print("! \(problem.kind): \(problem.text)") }
    }
} catch {
    FileHandle.standardError.write(Data("webcrawl: \(error)\n".utf8))
    exit(1)
}
