//// RSS connection, items of RSS and Atom feeds.
////
//// Each new item is a `FeedItem` event, see `guides/cloud/connections/rss.md`.

import cloud/connection
import cloud/connections/http
import cloud/connections/poller
import cloud/data
import gleam/list
import gleam/result
import gleam/string

pub fn start(
  name: String,
  feeds: List(String),
  every: Int,
  emit: fn(connection.Event) -> Nil,
) -> Nil {
  list.each(feeds, fn(feed) {
    poller.start(
      name,
      every,
      fn(_) {
        use body <- result.try(http.get(feed))
        from_feed(name, feed, body)
      },
      emit,
    )
  })
}

/// Convert an RSS or Atom document, items are newest first as feeds list them.
pub fn from_feed(
  name: String,
  feed: String,
  body: String,
) -> Result(List(poller.Item), String) {
  use items <- result.map(
    parse_feed(body) |> result.map_error(fn(reason) { feed <> ": " <> reason }),
  )
  list.map(items, fn(item) {
    let #(id, title, link, summary, published) = item
    let value =
      data.tagged(
        "FeedItem",
        data.record([
          #("connection", data.string(name)),
          #("feed", data.string(feed)),
          #("id", data.string(id)),
          #("title", data.string(title)),
          #("link", data.string(link)),
          #("summary", data.string(string.slice(summary, 0, 2000))),
          #("published", data.string(published)),
        ]),
      )
    poller.Item(id:, value:, summary: title)
  })
}

@external(erlang, "cloud_ffi", "parse_feed")
fn parse_feed(
  body: String,
) -> Result(List(#(String, String, String, String, String)), String)
