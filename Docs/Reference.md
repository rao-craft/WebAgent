# WebAgent reference

How the `web` agent is found, what a call takes and answers, the crawl step by step, the `webcrawl` command and how to
test it. What it is for is in the [README](../README.md); the agent standard it follows is in
[Schema/Web.md](../Schema/Web.md). The machinery is a library of its own, `WebCore` (no Granite), with a `webcrawl`
command beside it, so it can be lifted into anything else.

## How an app finds it

WebAgent is a `GraniteAgentPackage`, and it carries a record in its binary:

```swift
@used @section("__DATA_CONST,__granite")
let webRecord: GraniteRoster.Record = { GraniteRoster.record(WebAgent.self) }
```

In [Craft](https://github.com/riteshpakala/Craft), install it from the Agent Store or with
`craft agents add https://github.com/rao-craft/WebAgent.git`, then say `$web` in a request:

```
$web what changed in Swift 6.4? https://www.swift.org/blog/swift-6.4-released/
```

The model writes `{"query": "Swift 6.4 release notes"}`; the person's link rides the host's ask and is read without
being listed. The call shows on Craft's agent map as `web-1`, its steps as notes under it, and the model answers from
the sources, crediting each fact *(found on swift.org)* and ending with a short *Web work* section.

## What a call takes and answers

| Field | | |
|---|---|---|
| `query` | optional | what to search for, phrased for a search engine; left out, the person's own words are searched |
| `urls` | optional | pages to read directly; the links in the person's message are read without being listed here |
| `search` | optional | `false` reads the links alone and searches nothing |
| `depth` | optional | `1` also reads up to three same-site pages the linked pages link to, nearest the request first |
| `pages` | optional | how many pages to read, 1 to 12; 6 when left out |

The answer is a `WebResult` in `granite-answer/1`, with no file (`paths: []`):

```json
{
  "query": "Swift 6.4 release",
  "sources": [
    {"n": 1, "title": "Swift 6.4 Released", "url": "https://www.swift.org/blog/swift-6.4-released/", "site": "swift.org",
     "via": "prompt", "engines": [], "rendered": false, "excerpt": "Swift 6.4 is now available. …",
     "facts": [{"fact": "Swift 6.4 is now available.", "quote": "Swift 6.4 is now available."}]}
  ],
  "work": {
    "linked": ["https://www.swift.org/blog/swift-6.4-released/"],
    "searched": [{"engine": "DuckDuckGo", "query": "Swift 6.4 release", "hits": 10, "ms": 410}, …],
    "results": 45, "unique": 37,
    "crawled": [{"url": "https://www.swift.org/blog/swift-6.4-released/", "status": 200, "chars": 18211, "rendered": false, "ms": 380}, …],
    "skipped": [{"url": "https://developer.apple.com/swift/whats-new/", "why": "robots.txt asks not to"}],
    "skippedTotal": 1, "distilled": "model", "seconds": 7.8
  },
  "notes": ["Searched DuckDuckGo, Brave, Bing and Wikipedia for “Swift 6.4 release”: …", "…",
            "Answer from `sources`: credit each fact taken from them inline as (found on <site>) …",
            "End the reply with a short “Web work” section from `work`: …"],
  "problems": [{"kind": "engine", "text": "Brave gave nothing: answered 429."}],
  "paths": [], "made": [], "expected": [], "payloads": []
}
```

- `sources` are numbered in the order a reply may credit them: the person's links as written, then pages they link to
  (`depth: 1`), then the results in their fused order. `via` says which; `engines` says who found a result.
- `facts` carry a `quote` that is the page's own words. With the host's model the facts are the model's, and a fact
  whose quote is not on its page is dropped and counted in `problems`; without a model they are the page's sentences
  nearest the request (`work.distilled` says which).
- `work` is what the agent did, for the reply to account for; `skipped` names the first ten pages passed over and
  `skippedTotal` counts them all.
- `problems` kinds: `engine` (an engine busy or empty), `model` (the model could not read, or misquoted), `trim` (the
  answer was fitted, below).
- The answer stays under 20,000 characters, below Craft's 30,000 for a tool's answer: excerpts shorten first, then
  each page keeps fewer facts, then the last pages go, each step said in `problems`.

A call with no words and no link is refused as `call` (fix the call); a web out of reach (every engine and every link)
as `reach` (try later).

## The crawl

| Step | What |
|---|---|
| Links | `NSDataDetector` finds the links in the ask and in `urls`, bare or written out; each is normalized (no fragment, no `utm_*`, `gclid`, `fbclid`…; a sentence's closing punctuation dropped, a bracket the link opened kept) and kept once. |
| Query | `query`, else the ask without its links and tags (`$web`, `#canvas`, `@file`). |
| Engines | DuckDuckGo's HTML results, Brave Search's results page, Bing's results page (its `ck/a` links decoded) and Wikipedia's REST search, all at once; Google's Custom Search JSON API first when `GOOGLE_CSE_KEY` and `GOOGLE_CSE_CX` are set. A 429 or 503 is tried once more after 1.5 s. |
| Fusion | Reciprocal-rank fusion (k = 60) over the normalized address; a private address is never a result. |
| Isolation | One ephemeral `URLSession` per call: no cookie store, no cache, no credential or URL storage, every login challenge cancelled. User agent `WebAgent/1 (+https://github.com/rao-craft/WebAgent)`. |
| Hosts | http(s) only; `localhost`, `.local`, `.internal`, single-label names and private, loopback, link-local, carrier-grade NAT and multicast addresses refused; a name is resolved and refused when any address is private; every redirect (five at most) is checked again. |
| robots.txt | RFC 9309: the `webagent` group, else `*`; longest match wins, `Allow` on a tie; `*` and `$` understood; a missing file opens the site, a server error closes it. Kept for results and links one step deep; a page the person linked is read as asked. |
| Limits | 4 reads at once, 10 s a request, 2 MB a body, 6 pages (1–12), no read started after 45 s; a page that fails makes room for the next result. |
| Reading | HTML: the largest `article`, else `main`, else the body, without scripts, menus, headers, footers, asides, forms and cookie banners, block by block; title from `og:title`, published from `article:published_time` and the like. PDF: PDFKit's text, 60 pages at most. Text and JSON as they are. |
| WebKit | When the HTML's text is under 400 characters and the page is a script shell (`#root`, `#app`, `__NEXT_DATA__`…), a fresh windowless `WebPage` on a non-persistent data store loads it, waits for the load and 0.9 s more, and the drawn HTML is read. Navigation is held to public hosts; 15 s at most. |
| Facts | With the host's model: one structured call over each page's 2,400 characters nearest the request, at most 6 facts a page, each quote checked against the page. Without: each page's 3 sentences nearest the request (headings and menus left out). |

## The command

```sh
swift run webcrawl what changed in Swift 6.4 https://www.swift.org/blog/swift-6.4-released/
swift run webcrawl --query "Swift 6.4 release" --pages 4
swift run webcrawl --no-search --depth 1 https://www.swift.org/blog/
swift run webcrawl --json …                       # the sources and work as JSON
WEB_FIXTURES_DIR=Tests/Fixtures/web swift run webcrawl what changed in swift 6.4    # the recorded web
```

It runs with no host and no model, so its facts are the nearest sentences; its steps go to standard error.

## Testing

```sh
swift test                                              # engines, links, hosts, robots, fusion, reading, the run, the agent
WEB_LIVE=1 swift test --filter LiveTests                # the live web, and WebKit drawing a script-built page
WEB_BUILD=1 swift test --filter WebBuildTests           # installed with Granite's AgentInstaller, called over the wire
```

The suite reads a web recorded on 2026-11-11 (`Tests/Fixtures/web`, mapped by `index.json`): the four engines'
answers for "swift 6.4 release", four pages and their robots.txt. `RecordedFetcher` answers by the exact URL, then the
URL without its query (an engine's), so the same code runs with no network. See [TESTING.md](../TESTING.md).
