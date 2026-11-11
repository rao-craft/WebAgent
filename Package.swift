// swift-tools-version:6.0
// WebAgent: the web, read for a request, as a Granite agent package. It searches four engines at once (DuckDuckGo,
// Brave, Bing and Wikipedia; Google too when the person has a Programmable Search key), reads the links in the
// person's prompt and the best results in an isolated crawl (no cookies, no cache, no credentials, public hosts only,
// robots.txt kept), renders a page in WebKit when it needs JavaScript, and answers with the facts it found, each
// with the page it came from, and the work it did. The machinery is a library of its own, WebCore (no Granite), with
// the `webcrawl` command beside it. An app that links the package finds the `web` agent through Granite's roster,
// with nothing listed by hand.

import PackageDescription

let package = Package(
    name: "WebAgent",
    // WebKit's WebPage renders a page that needs JavaScript in-process, with no window: macOS 26.
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "WebAgent", targets: ["WebAgent"]),
        .library(name: "WebCore", targets: ["WebCore"]),
        .executable(name: "webcrawl", targets: ["webcrawl"]),
    ],
    dependencies: [
        .package(url: "https://github.com/riteshpakala/Granite.git", branch: "main"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.9.0"),
    ],
    targets: [
        // The machinery, extractable on its own: search, crawl, read, distill. No Granite, no UI.
        .target(
            name: "WebCore",
            dependencies: [.product(name: "SwiftSoup", package: "SwiftSoup")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(
            name: "WebAgent",
            dependencies: ["WebCore", .product(name: "GraniteAgents", package: "Granite")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        // `webcrawl what changed in swift 6.4 https://www.swift.org/blog/`: the same run from a terminal.
        .executableTarget(
            name: "webcrawl",
            dependencies: ["WebCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "WebCoreTests",
            dependencies: ["WebCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "WebAgentTests",
            dependencies: ["WebAgent", "WebCore", .product(name: "GraniteAgents", package: "Granite")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
