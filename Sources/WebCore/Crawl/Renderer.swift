import Foundation
import WebKit

/// A page drawn by a browser, for a page whose words its scripts write.
public struct Rendered: Sendable, Equatable {
    public var url: URL
    public var html: String
    public var text: String
}

/// How the crawl draws a page that needs JavaScript: WebKit, or nothing (tests, a run that must not).
public protocol Rendering: Sendable {
    func render(_ url: URL, timeout: TimeInterval) async throws -> Rendered
}

public enum RenderError: Error, CustomStringConvertible {
    case refused(String)
    case failed(String)
    case timedOut

    public var description: String {
        switch self {
        case .refused(let why): return why
        case .failed(let why): return "WebKit could not draw it: \(why)"
        case .timedOut: return "WebKit timed out"
        }
    }
}

/// WebKit with no window and nothing kept: a fresh `WebPage` per page on a data store that forgets, navigation held
/// to public http(s) hosts, no form ever submitted, no login ever answered.
///
/// PIN: ONE PAGE, THEN GONE. Each render makes its own page and drops it, so no page sees another's cookies or
/// storage, and a page cannot outlive its call. WebKit lives on main; the runner never blocks main.
public struct WebKitRenderer: Rendering {
    public init() {}

    public func render(_ url: URL, timeout: TimeInterval) async throws -> Rendered {
        guard HostGuard.check(url) == .allowed else { throw RenderError.refused("not a public web address") }
        return try await withThrowingTaskGroup(of: Rendered.self) { group in
            group.addTask { try await Self.draw(url) }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw RenderError.timedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw RenderError.timedOut }
            return first
        }
    }

    @MainActor
    static func draw(_ url: URL) async throws -> Rendered {
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.applicationNameForUserAgent = "WebAgent/1"
        let page = WebPage(configuration: configuration, navigationDecider: PublicOnly())
        page.customUserAgent = nil
        do {
            for try await event in page.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 12))
                where event == .finished {
                break
            }
        } catch {
            throw RenderError.failed("\(error)")
        }
        // Scripts that fetch after the load have a moment to write.
        try await Task.sleep(for: .milliseconds(900))
        let html = try await page.callJavaScript("return document.documentElement ? document.documentElement.outerHTML : ''") as? String ?? ""
        let text = try await page.callJavaScript("return document.body ? document.body.innerText : ''") as? String ?? ""
        return Rendered(url: page.url ?? url, html: html, text: text)
    }
}

/// Navigation to public http(s) hosts only; the main frame's page is read, a sub-frame elsewhere is never loaded.
@MainActor
private struct PublicOnly: WebPage.NavigationDeciding {
    func decidePolicy(for action: WebPage.NavigationAction, preferences: inout WebPage.NavigationPreferences) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        if url.scheme == "about" || url.scheme == "data" || url.scheme == "blob" { return .allow }
        return HostGuard.check(url) == .allowed ? .allow : .cancel
    }

    func decideAuthenticationChallengeDisposition(for challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust { return (.performDefaultHandling, nil) }
        return (.cancelAuthenticationChallenge, nil)
    }
}

/// No browser: a page that needs JavaScript is read as its HTML holds it.
public struct NoRenderer: Rendering {
    public init() {}
    public func render(_ url: URL, timeout: TimeInterval) async throws -> Rendered { throw RenderError.refused("rendering is off") }
}
