---
name: Hacker News and Lobsters connections
description: Run triggers on stories posted to Hacker News and Lobsters.
---

# Hacker News and Lobsters

Both connections poll public APIs, no accounts are needed.

```eyg
connections: [
  {name: "hn", source: HackerNews({lists: ["top"], every: 120}), channel: "news"},
  {name: "lobsters", source: Lobsters({lists: ["newest", "t/plt"], every: 120}), channel: "news"}
]
```

## Hacker News

`lists` are any of `top`, `new`, `best`, `ask` and `show`, read from the [official API](https://github.com/HackerNews/API).
Each poll checks the first 30 stories of each list and reports the ones not seen before.
A story already reported from one list is reported again when it appears on another, `list` says which.

```text
HackerNewsStory({connection, list, id, title, url, link, by, score, comments})
```

## Lobsters

`lists` are `hottest`, `newest`, or `t/<tag>` for a tag, read from the JSON pages Lobsters publishes.

```text
LobstersStory({connection, list, id, title, url, link, tags, submitter, score, comments})
```

## Example triggers

A story on the front page about Erlang:

```eyg
(event) -> {
  match event {
    HackerNewsStory(story) -> {
      match !equal(story.list, "top") {
        True(_) -> { cloud.triggers.title_contains("erlang")(event) }
        False(_) -> { False({}) }
      }
    }
    | (_) -> { False({}) }
  }
}
```

Scores and comment counts are as they were when the story was first seen, they are not updated.
For trends use the log, `perform Events("hn")` returns every story the connection has seen, newest first.

## Polling politely

Both sites are run by small teams. Keep `every` at a minute or more and watch only the lists you use.
