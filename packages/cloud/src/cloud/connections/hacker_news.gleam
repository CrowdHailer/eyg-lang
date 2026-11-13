//// Hacker News connection, stories on the front page lists.
////
//// Polls the official Firebase API, each new story is a `HackerNewsStory` event.

import cloud/connection
import cloud/connections/http
import cloud/connections/poller
import cloud/data
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/set
import gleam/string

const api = "https://hacker-news.firebaseio.com/v0/"

/// Stories checked on each poll, the first poll logs fewer.
const limit = 30

const first = 10

pub fn start(
  name: String,
  lists: List(String),
  every: Int,
  emit: fn(connection.Event) -> Nil,
) -> Nil {
  list.each(lists, fn(list_name) {
    poller.start(name, every, fn(seen) { fetch(name, list_name, seen) }, emit)
  })
}

fn fetch(name, list_name, seen) -> Result(List(poller.Item), String) {
  use body <- result.try(http.get(api <> list_name <> "stories.json"))
  use ids <- result.try(
    json.parse(body, decode.list(decode.int))
    |> result.map_error(string.inspect),
  )
  let count = case set.size(seen) {
    0 -> first
    _ -> limit
  }
  ids
  |> list.take(count)
  |> list.filter(fn(id) { !set.contains(seen, int.to_string(id)) })
  |> list.filter_map(fn(id) {
    use body <- result.try(
      http.get(api <> "item/" <> int.to_string(id) <> ".json")
      |> result.replace_error(Nil),
    )
    from_item(name, list_name, body) |> result.replace_error(Nil)
  })
  |> Ok
}

/// Convert an item of the API.
pub fn from_item(
  name: String,
  list_name: String,
  body: String,
) -> Result(poller.Item, String) {
  let decoder = {
    use id <- decode.field("id", decode.int)
    use title <- decode.optional_field("title", "", decode.string)
    let link = "https://news.ycombinator.com/item?id=" <> int.to_string(id)
    use url <- decode.optional_field("url", link, decode.string)
    use by <- decode.optional_field("by", "", decode.string)
    use score <- decode.optional_field("score", 0, decode.int)
    use comments <- decode.optional_field("descendants", 0, decode.int)
    let value =
      data.tagged(
        "HackerNewsStory",
        data.record([
          #("connection", data.string(name)),
          #("list", data.string(list_name)),
          #("id", data.int(id)),
          #("title", data.string(title)),
          #("url", data.string(url)),
          #("link", data.string(link)),
          #("by", data.string(by)),
          #("score", data.int(score)),
          #("comments", data.int(comments)),
        ]),
      )
    decode.success(poller.Item(id: int.to_string(id), value:, summary: title))
  }
  json.parse(body, decoder) |> result.map_error(string.inspect)
}
