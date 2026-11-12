//// Message history uses an exclusive `after` snowflake, not a cursor envelope.

import cloud/discord/api/schema
import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option, None, Some}
import midas/continuation.{type Continuation as K}

pub type Page(a) {
  Page(data: a, next_cursor: Option(String))
}

/// Each page is newest-first; the first ID advances to the next newer page.
pub fn decoder() -> decode.Decoder(Page(List(schema.Message))) {
  use messages <- decode.then(decode.list(schema.message_decoder()))
  let next_cursor = case messages, list.length(messages) {
    [newest, ..], 100 -> Some(newest.id)
    _, _ -> None
  }
  decode.success(Page(messages, next_cursor))
}

/// Return page payloads in fetch order, stopping at the first short page.
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
    None -> continuation.done(list.reverse(acc))
    cursor -> fetch_pages(fetch_page, cursor, acc)
  }
}
