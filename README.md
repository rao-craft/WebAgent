# WebAgent

Look anything up on the web from Craft. Say `$web` in a request, or paste a link, and `web` searches four engines at
once, reads your links and the best results in an isolated crawl, and hands the model the facts it found, each with
the page it came from. The reply credits them as it goes (*found on swift.org*) and ends with what the agent did: the
engines it searched, the pages it read, and anything it passed over.

## What you can ask

```
$web what changed in Swift 6.4?
$web summarize https://www.swift.org/blog/swift-6.4-released/
$web compare the pricing on https://example.com/pricing with its two closest competitors
$web read https://www.swift.org/blog/ and the posts it links to about Swift 6.4
```

A link in your message is read as it is; `$web` with words alone searches. Craft writes the call, shows each step on
its agent map as the agent works, and the model answers from what came back.

## What you get

- **Facts with their sources.** Every page read is numbered with its title, site and address, the words on it nearest
  your request, and the facts it holds, each with the page's own words that say it. With Craft's model loaded, the
  model reads the pages for the facts and a fact is kept only when its quote is really on the page; without one, the
  sentences nearest the request are kept as they are.
- **A reply that credits them.** The model is told to credit each fact inline as *(found on swift.org)*, to cite no page
  it was not given, and to say plainly what the pages do not cover.
- **The work, shown.** The reply ends with a short *Web work* section: the engines searched and the query, how many
  results and distinct pages, the pages read by site, and what was skipped and why. The same steps stream on the
  agent's card while it runs (*Searching DuckDuckGo, Brave, Bing and Wikipedia…*, *Read 3/6: swift.org*).
- **No files.** The answer is the work: nothing is written to your project and no build is owed.

## How it works

- **Four engines, every call.** DuckDuckGo, Brave Search, Bing and Wikipedia are asked at once, with no account or
  key. Google is added when you set your own Programmable Search key (`GOOGLE_CSE_KEY` and `GOOGLE_CSE_CX` in Craft's
  environment). An engine that is busy or gives nothing is noted, and the rest carry on.
- **Results fused.** Reciprocal-rank fusion puts a page several engines rank well first, and keeps which engines found
  it.
- **An isolated crawl.** Each call runs in a process of its own with a web session of its own: no cookies, no cache,
  no saved logins, no credentials ever offered. Only public hosts over http(s) are read: an address on your Mac or
  your network, or a name that resolves to one, is refused, before the request and after every redirect. Bodies stop
  at 2 MB, requests at 10 seconds, the crawl at 6 pages (up to 12) and about 45 seconds.
- **robots.txt kept.** Every page the agent finds on its own is read only when the site's robots.txt allows
  `WebAgent`. A page you linked yourself is your request, so it is read as you asked.
- **WebKit when a page needs it.** A page whose words its scripts write is drawn in a windowless WebKit page that keeps
  nothing (a data store of its own, dropped after the page) and navigates only to public hosts, then read.
- **HTML, PDF and text.** Pages are read for their main text without menus, banners and footers; PDFs for their text.

## Coming soon

- **Web sources in Craft's Sources sheet.** Today Craft's Sources sheet and its brushstrokes credit the code and files
  a reply drew on. Web pages will join them there. Until then, `web` hands its sources to the model, and the reply
  credits them inline.

## Get it

In Craft, install Web from the Agent Store, or run `craft agents add https://github.com/rao-craft/WebAgent.git`, then
say `$web` in a request. It's free.

## Requirements

- A Mac on macOS 26 or later (WebKit's windowless page).
- A network connection; no account or API key. Google needs your own Programmable Search key.
- Questions asked in Craft's ask mode stop before agents run: ask in a normal turn.
- MIT licensed. HTML is parsed with [SwiftSoup](https://github.com/scinfu/SwiftSoup) (MIT).

## For developers

What a call takes and answers, the crawl step by step and the `webcrawl` command are in the
[reference](Docs/Reference.md). The machinery is a library of its own, `WebCore` (no Granite), so it can be lifted into
anything else. The agent standard it follows is [Schema/Web.md](Schema/Web.md), and how it is tested is
[TESTING.md](TESTING.md).
