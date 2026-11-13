//// Bluesky connection, posts by accounts and in feeds.
////
//// Polls the public AppView, no account is needed.
//// Each post is reported as a `BskyPost` event, reposts are skipped.

import cloud/connection
import cloud/connections/http
import cloud/connections/poller
import cloud/data
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import gleam/uri

const appview = "https://public.api.bsky.app/xrpc/"

pub fn start(
  name: String,
  actors: List(String),
  feeds: List(String),
  every: Int,
  emit: fn(connection.Event) -> Nil,
) -> Nil {
  list.each(actors, fn(actor) {
    let url =
      appview
      <> "app.bsky.feed.getAuthorFeed?filter=posts_no_replies&limit=30&actor="
      <> uri.percent_encode(actor)
    poller.start(name, every, fn(_) { fetch(name, url, "@" <> actor) }, emit)
  })
  list.each(feeds, fn(feed) {
    let url =
      appview
      <> "app.bsky.feed.getFeed?limit=30&feed="
      <> uri.percent_encode(feed)
    poller.start(name, every, fn(_) { fetch(name, url, feed) }, emit)
  })
}

fn fetch(name, url, source) -> Result(List(poller.Item), String) {
  use body <- result.try(http.get(url))
  from_feed(name, source, body)
}

/// Convert a feed response, `source` is the account or feed it came from.
pub fn from_feed(
  name: String,
  source: String,
  body: String,
) -> Result(List(poller.Item), String) {
  let post = {
    use reason <- decode.optional_field("reason", False, decode.success(True))
    use uri <- decode.subfield(["post", "uri"], decode.string)
    use handle <- decode.subfield(["post", "author", "handle"], decode.string)
    use author <- decode.then(decode.optionally_at(
      ["post", "author", "displayName"],
      handle,
      decode.string,
    ))
    use text <- decode.then(decode.optionally_at(
      ["post", "record", "text"],
      "",
      decode.string,
    ))
    use created_at <- decode.then(decode.optionally_at(
      ["post", "record", "createdAt"],
      "",
      decode.string,
    ))
    use reply <- decode.then(decode.optionally_at(
      ["post", "record", "reply"],
      False,
      decode.success(True),
    ))
    use likes <- decode.then(count("likeCount"))
    use reposts <- decode.then(count("repostCount"))
    use replies <- decode.then(count("replyCount"))
    let value =
      data.tagged(
        "BskyPost",
        data.record([
          #("connection", data.string(name)),
          #("uri", data.string(uri)),
          #("url", data.string(web_url(handle, uri))),
          #("author", data.string(author)),
          #("account", data.string(handle)),
          #("text", data.string(text)),
          #("created_at", data.string(created_at)),
          #("reply", data.bool(reply)),
          #("likes", data.int(likes)),
          #("reposts", data.int(reposts)),
          #("replies", data.int(replies)),
          #("source", data.string(source)),
        ]),
      )
    let summary = "@" <> handle <> ": " <> string.slice(text, 0, 60)
    decode.success(#(reason, poller.Item(id: uri, value:, summary:)))
  }
  json.parse(body, decode.at(["feed"], decode.list(post)))
  |> result.map_error(string.inspect)
  |> result.map(
    list.filter_map(_, fn(post) {
      case post {
        #(False, item) -> Ok(item)
        #(True, _) -> Error(Nil)
      }
    }),
  )
}

fn count(field) {
  decode.optionally_at(["post", field], 0, decode.int)
}

/// `https://bsky.app/profile/<handle>/post/<rkey>` for `at://<did>/app.bsky.feed.post/<rkey>`.
pub fn web_url(handle: String, uri: String) -> String {
  let rkey = string.split(uri, "/") |> list.last |> result.unwrap("")
  "https://bsky.app/profile/" <> handle <> "/post/" <> rkey
}
