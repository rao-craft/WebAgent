import Foundation
import PDFKit
import SwiftSoup

/// A page's words as a reader sees them: its title, its site, when it was published, and its main text without
/// the menus, banners, footers and scripts around it.
public struct Readable: Sendable, Equatable {
    public var title: String
    public var site: String?
    public var published: String?
    public var text: String
    /// Same-site links in the main text.
    public var links: [URL]
    /// The page writes its words with scripts: what the HTML holds is a shell.
    public var scripted: Bool

    static let dropped = "script, style, noscript, template, svg, canvas, iframe, form, button, select, nav, header, footer, aside, "
        + "[role=navigation], [role=banner], [role=contentinfo], [role=complementary], [aria-hidden=true], [hidden], "
        + ".cookie, .cookies, #cookie-banner, .advert, .ads, .sidebar, .share, .social, .newsletter"
    static let blocks: Set<String> = ["p", "h1", "h2", "h3", "h4", "h5", "h6", "li", "pre", "blockquote", "td", "th", "dt", "dd",
                                      "figcaption", "caption", "summary"]

    public init(html: String, url: URL) {
        let document: Document
        do {
            document = try SwiftSoup.parse(html, url.absoluteString)
        } catch {
            self.init(title: "", site: nil, published: nil, text: "", links: [], scripted: false)
            return
        }
        let meta = { (selector: String) -> String? in
            guard let value = try? document.select(selector).first()?.attr("content"), !value.isEmpty else { return nil }
            return value
        }
        let title = meta("meta[property=og:title]") ?? (try? document.title()).flatMap { $0.isEmpty ? nil : $0 }
            ?? (try? document.select("h1").first()?.text()) ?? ""
        let site = meta("meta[property=og:site_name]") ?? meta("meta[name=application-name]")
        let published = meta("meta[property=article:published_time]") ?? meta("meta[name=date]") ?? meta("meta[itemprop=datePublished]")
            ?? (try? document.select("time[datetime]").first()?.attr("datetime")).flatMap { $0.isEmpty ? nil : $0 }
        let scripts = (try? document.select("script[src], script:not([type=application/ld+json])").size()) ?? 0
        let shell = html.contains("id=\"root\"") || html.contains("id=\"app\"") || html.contains("id=\"__next\"")
            || html.contains("__NEXT_DATA__") || html.contains("window.__NUXT__") || html.contains("ng-version")

        _ = try? document.select(Self.dropped).remove()
        let root = Self.mainRoot(document)
        let text = Self.text(of: root)
        var links: [URL] = []
        var seen = Set<String>()
        if let anchors = try? root.select("a[href]") {
            for anchor in anchors {
                guard let href = try? anchor.absUrl("href"), let raw = URL(string: href), let link = URLNormal.normalized(raw),
                      URLNormal.site(link) == URLNormal.site(url), URLNormal.key(link) != URLNormal.key(url) else { continue }
                if seen.insert(URLNormal.key(link)).inserted { links.append(link) }
            }
        }
        self.init(title: Self.clean(title), site: site.map(Self.clean), published: published, text: text, links: links,
                  scripted: text.count < 400 && (shell || scripts > 4))
    }

    init(title: String, site: String?, published: String?, text: String, links: [URL], scripted: Bool) {
        self.title = title; self.site = site; self.published = published; self.text = text; self.links = links; self.scripted = scripted
    }

    /// The article, else the main element, else the body: the one with the most words wins among articles.
    static func mainRoot(_ document: Document) -> Element {
        if let articles = try? document.select("article"), articles.size() > 0 {
            let best = articles.array().max { ((try? $0.text().count) ?? 0) < ((try? $1.text().count) ?? 0) }
            if let best, ((try? best.text().count) ?? 0) > 200 { return best }
        }
        for selector in ["main", "[role=main]", "#content", ".content", "#main"] {
            if let found = try? document.select(selector).first(), ((try? found.text().count) ?? 0) > 200 { return found }
        }
        return document.body() ?? document
    }

    /// Block by block, one line each, so sentences of different blocks never run together.
    static func text(of root: Element) -> String {
        var lines: [String] = []
        var last = ""
        func walk(_ element: Element) {
            let tag = element.tagName().lowercased()
            if blocks.contains(tag) {
                let line = clean((try? element.text()) ?? "")
                if !line.isEmpty, line != last {
                    lines.append(tag.hasPrefix("h") && tag.count == 2 ? "## " + line : line)
                    last = line
                }
                return
            }
            for child in element.children() { walk(child) }
        }
        walk(root)
        let joined = lines.joined(separator: "\n")
        // A page of divs and spans has no blocks: its whole text, as one.
        if joined.count < 200 { return clean((try? root.text()) ?? "") }
        return joined
    }

    static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{00a0}", with: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\r" || $0 == "\n" })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// A PDF's text, page by page; its title from its own properties.
    public static func pdf(_ data: Data, url: URL) -> Readable? {
        guard let document = PDFDocument(data: data) else { return nil }
        var pages: [String] = []
        for index in 0..<min(document.pageCount, 60) {
            if let text = document.page(at: index)?.string { pages.append(text) }
        }
        let title = (document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String) ?? url.lastPathComponent
        let text = pages.joined(separator: "\n").split(whereSeparator: \.isNewline).map { clean(String($0)) }.filter { !$0.isEmpty }
            .joined(separator: "\n")
        return Readable(title: title, site: nil, published: nil, text: text, links: [], scripted: false)
    }
}
