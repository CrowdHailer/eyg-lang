//// Cursor-based pagination: https://docs.slack.dev/apis/web-api/pagination/

import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option, None, Some}
import midas/continuation.{type Continuation as K}

/// Keep the operation's payload intact, including any operation-specific metadata.
pub type Page(a) {
  Page(data: a, next_cursor: Option(String))
}

/// Decode a payload and Slack's optional response_metadata.next_cursor envelope.
pub fn decoder(data_decoder: decode.Decoder(a)) -> decode.Decoder(Page(a)) {
  use data <- decode.then(data_decoder)
  let cursor_decoder =
    decode.optional_field(
      "next_cursor",
      None,
      decode.optional(decode.string),
      decode.success,
    )
  use next_cursor <- decode.optional_field(
    "response_metadata",
    None,
    decode.optional(cursor_decoder) |> decode.map(option.unwrap(_, None)),
  )
  let next_cursor = case next_cursor {
    Some("") -> None
    cursor -> cursor
  }
  decode.success(Page(data, next_cursor))
}

/// Fetch every page payload in order. Only the cursor determines completion;
/// short or empty collections may still have another page. Errors propagate.
/// Callers can flatten list payloads while retaining metadata for other payloads.
pub fn fetch_all(
  fetch_page: fn(Option(String)) -> K(t, Result(Page(a), error)),
) -> K(t, Result(List(a), error)) {
  fetch_pages(fetch_page, None, [])
}

fn fetch_pages(
  fetch_page: fn(Option(String)) -> K(t, Result(Page(a), error)),
  cursor: Option(String),
  acc: List(a),
) -> K(t, Result(List(a), error)) {
  use page <- continuation.try_then(fetch_page(cursor))
  let acc = [page.data, ..acc]
  case page.next_cursor {
    None | Some("") -> continuation.done(list.reverse(acc))
    cursor -> fetch_pages(fetch_page, cursor, acc)
  }
}
