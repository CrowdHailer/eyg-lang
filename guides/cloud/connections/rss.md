---
name: RSS connection
description: Run triggers on new items in RSS and Atom feeds.
---

# RSS and Atom feeds

An `Rss` connection polls feeds and reports each new item as a `FeedItem` event to its channel's triggers.

```eyg
{
  name: "blogs",
  source: Rss({feeds: ["https://gleam.run/feed.xml", "https://erlangforums.com/latest.rss"], every: 300}),
  channel: "news"
}
```

- `feeds` are feed URLs, RSS 2.0 and Atom are both read.
- `every` is the seconds between polls, 300 by default. Be kind to small sites.

Items found on the first poll are logged without running triggers, later items run them.
An item is identified by its `guid` or `id`, or its link when it has neither, so edited items are not reported again.

## Events

```text
FeedItem({connection, feed, id, title, link, summary, published})
```

`summary` is the item's description, summary or content, it may contain HTML.
`published` is the date as the feed writes it, RSS feeds use RFC 822 and Atom feeds ISO 8601.

## Example triggers

Post items about a topic, `cloud.triggers.title_contains` ignores case:

```eyg
{
  name: "gleam-news",
  pattern: cloud.triggers.title_contains("gleam"),
  script: match {
    FeedItem(item) -> { perform Post(!string_append(item.title, !string_append(" ", item.link))) }
    | (_) -> { Ok("") }
  }
}
```

Ask an agent for a summary of long posts with `perform Delegate(...)` in the script,
the subagent runs with the channel's shell, so it can only fetch what the channel may fetch.

Read the items the connection has seen with `perform Events("blogs")`, for example to post a daily digest from a cron.
