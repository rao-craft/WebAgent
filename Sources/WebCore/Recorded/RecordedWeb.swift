import Foundation

/// The web as recorded: a folder whose `index.json` maps a URL (or a URL without its query, for an engine whose
/// query varies) to a file of its answer, so tests and a Mac without a network run the same code.
/// `WEB_FIXTURES_DIR` names the folder.
///
/// ```json
/// {"https://www.swift.org/blog/swift-6.4-released/": {"file": "swift-blog.html", "type": "text/html"},
///  "https://www.bing.com/search": {"file": "bing.html", "type": "text/html"},
///  "https://example.com/robots.txt": {"status": 404}}
/// ```
public struct RecordedFetcher: Fetching {
    public static let variable = "WEB_FIXTURES_DIR"

    struct Entry: Decodable {
        var file: String?
        var type: String?
        var status: Int?
        /// Where the request ends, when it redirects.
        var url: String?
    }

    let folder: URL
    let entries: [String: Entry]

    public var resolvesHosts: Bool { false }

    public init(folder: URL) throws {
        self.folder = folder
        entries = try JSONDecoder().decode([String: Entry].self, from: Data(contentsOf: folder.appendingPathComponent("index.json")))
    }

    /// The recorded web the environment names, if it names one.
    public static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> RecordedFetcher? {
        guard let path = environment[variable], !path.isEmpty else { return nil }
        return try? RecordedFetcher(folder: URL(fileURLWithPath: path, isDirectory: true))
    }

    public func fetch(_ request: FetchRequest) async throws -> Fetched {
        let exact = request.url.absoluteString
        var bare = URLComponents(url: request.url, resolvingAgainstBaseURL: false)
        bare?.query = nil
        guard let entry = entries[exact] ?? bare?.string.flatMap({ entries[$0] }) else { throw FetchError.unrecorded(exact) }
        let data = try entry.file.map { try Data(contentsOf: folder.appendingPathComponent($0)) } ?? Data()
        return Fetched(url: entry.url.flatMap(URL.init(string:)) ?? request.url, status: entry.status ?? 200, mimeType: entry.type,
                       data: data.prefix(request.maxBytes), truncated: data.count > request.maxBytes)
    }
}
