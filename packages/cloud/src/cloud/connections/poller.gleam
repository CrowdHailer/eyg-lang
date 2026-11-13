//// Poll a service for items and report the new ones as events.
////
//// The first poll reports every item it finds as not live, they are logged and run no triggers.
//// Later polls report items not seen before as live.

import cloud/connection
import cloud/data
import gleam/erlang/process
import gleam/io
import gleam/list
import gleam/set.{type Set}

pub type Item {
  Item(id: String, value: data.Value, summary: String)
}

/// Poll `fetch` every `every` seconds in a new process, `fetch` returns items newest first.
/// `fetch` is given the ids already seen, so it can skip fetching their details.
pub fn start(
  name: String,
  every: Int,
  fetch: fn(Set(String)) -> Result(List(Item), String),
  emit: fn(connection.Event) -> Nil,
) -> Nil {
  process.spawn(fn() { poll(name, every, fetch, emit, set.new(), False) })
  Nil
}

fn poll(name, every, fetch, emit, seen, live) -> Nil {
  let seen = case fetch(seen) {
    Ok(items) ->
      items
      |> list.reverse
      |> list.fold(seen, fn(seen, item) {
        let Item(id:, value:, summary:) = item
        case set.contains(seen, id) {
          True -> seen
          False -> {
            emit(connection.Event(name, id, value, summary, live))
            set.insert(seen, id)
          }
        }
      })
    Error(reason) -> {
      io.println_error(name <> ": " <> reason)
      seen
    }
  }
  process.sleep(every * 1000)
  poll(name, every, fetch, emit, seen, True)
}
