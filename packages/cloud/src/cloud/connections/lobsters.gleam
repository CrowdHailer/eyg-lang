//// Lobsters connection, stories on Lobsters lists.
////
//// Polls the JSON pages, `hottest`, `newest` or `t/<tag>`, each new story is a `LobstersStory` event.

import cloud/connection
import cloud/connections/http
import cloud/connections/poller
import cloud/data
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub fn start(
  name: String,
  lists: List(String),
  every: Int,
  emit: fn(connection.Event) -> Nil,
) -> Nil {
  list.each(lists, fn(list_name) {
    let url = "https://lobste.rs/" <> list_name <> ".json"
    poller.start(
      name,
      every,
      fn(_) {
        use body <- result.try(http.get(url))
        from_page(name, list_name, body)
      },
      emit,
    )
  })
}

/// Convert a JSON page of stories.
pub fn from_page(
  name: String,
  list_name: String,
  body: String,
) -> Result(List(poller.Item), String) {
  let story = {
    use id <- decode.field("short_id", decode.string)
    use title <- decode.field("title", decode.string)
    use link <- decode.field("comments_url", decode.string)
    use url <- decode.optional_field("url", "", decode.string)
    use tags <- decode.optional_field("tags", [], decode.list(decode.string))
    use submitter <- decode.optional_field(
      "submitter_user",
      "",
      decode.one_of(decode.string, [decode.at(["username"], decode.string)]),
    )
    use score <- decode.optional_field("score", 0, decode.int)
    use comments <- decode.optional_field("comment_count", 0, decode.int)
    let url = case url {
      "" -> link
      url -> url
    }
    let value =
      data.tagged(
        "LobstersStory",
        data.record([
          #("connection", data.string(name)),
          #("list", data.string(list_name)),
          #("id", data.string(id)),
          #("title", data.string(title)),
          #("url", data.string(url)),
          #("link", data.string(link)),
          #("tags", data.strings(tags)),
          #("submitter", data.string(submitter)),
          #("score", data.int(score)),
          #("comments", data.int(comments)),
        ]),
      )
    decode.success(poller.Item(id:, value:, summary: title))
  }
  json.parse(body, decode.list(story)) |> result.map_error(string.inspect)
}
