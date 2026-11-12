# Testing WebAgent

How `web` is tested: its own suite on a recorded web, its gated live runs, its gated install of a real runner, and
calls run on this Mac, each logged below with what came out. The suite never reaches the live web: it reads the
engines' answers and pages recorded on 2026-11-11 (`Tests/Fixtures/web`). Runs marked live searched and crawled the web
itself.

## The suite

```
swift test                                              # engines, links, hosts, robots, fusion, reading, the run, the agent
WEB_LIVE=1 swift test --filter LiveTests                # the live web, and WebKit drawing a script-built page (gated)
WEB_BUILD=1 swift test --filter WebBuildTests           # installed with Granite's AgentInstaller, called over the wire (gated, minutes)
```

What it pins:

- **The engines**: DuckDuckGo's ten results in order with ads dropped and its `uddg` links unwrapped; Brave's web
  results only, with their titles and snippets; Bing's ten, its `ck/a` links decoded; Wikipedia's search with its
  markup gone; Google only with both a key and an engine id.
- **Fusion**: a page two engines found first, its engines best rank first, its longest snippet, tracking parameters
  dropped, a private address never a result.
- **Links and hosts**: links bare or written out, a bracket the link opened kept and a sentence's closing punctuation
  dropped, one spelling per page; loopback, private, link-local, carrier-grade NAT, `.local`, single-label and
  non-http addresses refused.
- **robots.txt**: the agent's own group before everyone's, the longest rule deciding, `*` and `$`, a server error
  closing the site.
- **Reading**: the swift.org post's words without its chrome; the docs.swift.org shell known as script-built; blocks
  never run together; the nearest sentences as facts, each its own quote; a quote checked against its page.
- **The run**: four engines and 45 results for "what changed in Swift 6.4", three pages read in fused order, two sites
  skipped for robots.txt, the notes that say how to credit and account; the person's links first and read as asked,
  even where robots.txt closes the site; a model's misquoted fact dropped and counted; an engine down as a problem; no
  words and no link refused as `call`; every engine out of reach refused as `reach`.
- **The agent**: its record, the schema a model sees, the guide, a call through the roster with the person's link in
  the ask, a refusal's kind, a big answer fitted under its limit.

## Runs on this Mac

### In Craft: a made-up link that looped (fixed)

*2026-11-12 · Craft, the local model (Qwopus3.5-122B) · live web*

Asked to find a comet shader with `$web` and put it in `index.html`, the model searched twice (both answered), then
called `{"query": "CosmosMuseum cosmos-meteor-shower index.html source code", "search": false, "urls":
["https://github.com/CosmosMuseum/cosmos-meteor-shower"]}`: a repository that does not exist. GitHub answered 404, and
web refused as `reach` ("The web is out of reach from this Mac: github.com answered 404. Try again when it is
online."), so the model called again with the same link three times while Craft held the edit for the required `$web`.

After the fix, the same call from a terminal:

```sh
swift run webcrawl --query "realistic comet GLSL shader" --no-search https://github.com/CosmosMuseum/cosmos-meteor-shower
```

**Notes**: `Skipped github.com: answered 404` · `The link could not be read; searching for “realistic comet GLSL shader”
instead` · `21 results, 14 distinct pages` · `Read 4/6: shader.gallery (drawn in WebKit)` … `12 facts from 6 pages`.
Pinned by `testALinkThatIsGoneFallsBackToTheSearch` and `testALinkThatIsGoneWithNothingToSearchIsTheCallsToFix`.

Setup: MacBook Pro M4 Max, macOS 27, Swift 6.4.2, the agent installed into Craft with `craft agents add`.

### Live: a question and a link

*2026-11-11 · live web · no model · 7.8 s*

```sh
swift run webcrawl what changed in Swift 6.4 https://www.swift.org/blog/swift-6.4-released/
```

**Notes**: `Reading the link in the prompt` · `Searching DuckDuckGo, Brave, Bing and Wikipedia for “what changed in Swift
6.4”` · `25 results, 16 distinct pages` · `Read 1/6: swift.org` … `Read 5/6: docs.swift.org (drawn in WebKit)` ·
`16 facts from 6 pages`

**Came out**: six sources, the person's link first (swift.org, then swiftprogramming.com, avanderlee.com,
developer.apple.com, medium.com, docs.swift.org), docs.swift.org drawn in WebKit because its words are written by its
scripts. Brave answered 429 (busy, after many runs from this Mac that hour) and was counted as a problem; the other
three engines and the link carried the call.

### Gated suites

*2026-11-11*: `WEB_LIVE=1` passed (8.5 s and 2.3 s); `WEB_BUILD=1` passed (196 s: a release build of the runner,
`--describe` answering `web`, and a recorded call over the wire).
