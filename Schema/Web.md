# craft-agent/1 · web

Looks a request up on the web: it searches DuckDuckGo, Brave, Bing and Wikipedia at once, reads the links in the prompt and the best results in an isolated crawl (WebKit for pages that need JavaScript), and answers with the facts it found, each with the page it came from, and the work it did.

web's copy of Craft's agent standard (`craft-agent/1`, Craft's `Schema/Agent.md`), written by
`craft agents schema web` from its record. Everything above **Changes** is written again each time; Changes is
web's own log.

| File | What it holds |
| --- | --- |
| [`web.input.schema.json`](web.input.schema.json) | What it takes, as JSON Schema |
| [`web.answer.schema.json`](web.answer.schema.json) | What it answers: `granite-answer/1` with its own kinds |

## What it takes

| Field | Required | What it is |
| --- | --- | --- |
| `query` | no | what to search for, phrased for a search engine: the subject, names, versions, dates; left out, the person's own words are searched |
| `urls` | no | pages to read directly, when the person named or linked them; the links in the person's message are read without being listed here |
| `search` | no | false reads the links alone and searches nothing; left out, the engines are searched too |
| `depth` | no | 1 also reads up to three pages on the same site that the linked pages link to, nearest the request first; 0 or left out reads only the pages themselves |
| `pages` | no | how many pages to read, 1 to 12; 6 when left out |

`directory` is filled by Craft with the project folder. The person's request and the host's model are offered
beside the call, never in it.

## What it makes

Nothing declared yet (`makes`): Craft holds no file for it and measures no `made`.

## What it answers

A `granite-answer/1` answer (Granite's `Schema/GraniteAgent.md` §4.2): `paths`, `made` against `expected` by kind and
name, `problems` for what it could only do in part, `payloads` for files that keep a standard of their own, and its
own keys beside them. Craft measures each call by what it made of what it expected.

## How it refuses

With an `AgentRefusal`: a kind and reasons, each with its fix. `input` and `call` are the call's to correct; `build`,
`device`, `reach`, `model` and `host` what stood in the way; `answer` and `parse` its own bug.

## Changes

Each change made to make this agent more precise, dated, with the regime run that measured it and what it
made of what it was asked before and after (`TESTING.md`). Newest first.

### 2026-11-11 · the first version: sources and work in the answer

web answers `granite-answer/1` with no file (`paths: []`) and two keys of its own: `sources`, the pages read, numbered, each with its site, an excerpt and facts whose `quote` is the page's own words; and `work`, the engines searched, the pages read and skipped, and how the facts were found. Its `notes` tell the model to credit each fact inline as (found on <site>) and to end the reply with a short "Web work" section. A call with nothing to look up is refused as `call`; a web out of reach as `reach`. Web sources in Craft's own Sources sheet are to come, and need Craft.

Measured: not yet; the first regime chain is the first measure.
