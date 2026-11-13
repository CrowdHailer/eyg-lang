---
name: Bluesky connection
description: Run triggers on Bluesky posts by accounts and in feeds, and query the log of posts.
---

# Bluesky

A Bluesky connection polls the public AppView, no account or app password is needed.

```eyg
{
  name: "bsky",
  source: Bsky({
    actors: ["gleam.run"],
    feeds: ["at://did:plc:z72i7hdynmk6r22z27h6tvur/app.bsky.feed.generator/whats-hot"],
    every: 30
  }),
  channel: "social"
}
```

- `actors` are accounts, by handle or DID, their posts are reported, replies and reposts are not.
- `feeds` are feed generators, every new post in the feed is reported.

Each post is a `BskyPost` event, see [trigger events](../trigger_events.md#bluesky).

## Querying the log

Every post the connection has seen is kept in its log, newest first.
A trigger's script reads it with the `Events` effect, so a trigger can decide using more than the one event.
This script from the [example workspace](../../../examples/cloud/workspace.eyg) counts how many posts by the same account are in the log:

```eyg
match event {
  BskyPost(post) -> {
    let seen = match perform Events("bsky") {
      Ok(events) -> {
        !list_fold(events, 0, (event, count) -> {
          match event {
            BskyPost(other) -> {
              match !equal(other.account, post.account) {
                True(_) -> { !int_add(count, 1) }
                False(_) -> { count }
              }
            }
            | (_) -> { count }
          }
        })
      }
      Error(_) -> { 0 }
    }
    perform Post(!string_append("Posts in the log by this account: ", !int_to_string(seen)))
  }
  | (_) -> { {} }
}
```

The pattern stays pure, the script performs `Events`, which the channel shell must allow with an `events` gate.
