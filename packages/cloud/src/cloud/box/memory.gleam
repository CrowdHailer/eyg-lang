//// Boxes that are only kept in memory, as blobs are in the memory blob store.
//// A box is kept here until a session is made in it, then its events are recorded in Postgres, see `box.durable`.
//// A box that no session was made in is lost when the service stops.

import cloud/data/boxes.{type Box}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{type Option, Some}
import gleam/otp/actor
import gleam/result
import gleam/string

/// The state of a box after each of its events, with the change each event merged.
pub type Events =
  List(#(Box, Option(String)))

pub opaque type Message {
  Add(box: Box, reply: Subject(Bool))
  Record(box: Box, change: Option(String))
  Get(id: String, reply: Subject(Result(Box, Nil)))
  Merged(id: String, change: String, reply: Subject(Bool))
  Named(reply: Subject(List(Box)))
  Take(id: String, reply: Subject(Result(Events, Nil)))
}

pub type Memory =
  Subject(Message)

pub fn start() -> actor.StartResult(Memory) {
  actor.new(dict.new())
  |> actor.on_message(handle)
  |> actor.start
}

fn handle(kept: Dict(String, Events), message) {
  case message {
    Add(box, reply) -> {
      let taken =
        box.name != option.None
        && list.any(dict.values(kept), fn(events) {
          case events {
            [#(latest, _), ..] -> latest.name == box.name
            [] -> False
          }
        })
      process.send(reply, !taken)
      case taken {
        True -> actor.continue(kept)
        False ->
          actor.continue(dict.insert(kept, box.id, [#(box, option.None)]))
      }
    }
    Record(box, change) -> {
      let events = dict.get(kept, box.id) |> result.unwrap([])
      actor.continue(dict.insert(kept, box.id, [#(box, change), ..events]))
    }
    Get(id, reply) -> {
      process.send(reply, case dict.get(kept, id) {
        Ok([#(box, _), ..]) -> Ok(box)
        _ -> Error(Nil)
      })
      actor.continue(kept)
    }
    Merged(id, change, reply) -> {
      let events = dict.get(kept, id) |> result.unwrap([])
      process.send(
        reply,
        list.any(events, fn(event) { event.1 == Some(change) }),
      )
      actor.continue(kept)
    }
    Named(reply) -> {
      dict.values(kept)
      |> list.filter_map(fn(events) {
        case events {
          [#(box, _), ..] if box.name != option.None -> Ok(box)
          _ -> Error(Nil)
        }
      })
      |> list.sort(fn(a, b) {
        string.compare(option.unwrap(a.name, ""), option.unwrap(b.name, ""))
      })
      |> process.send(reply, _)
      actor.continue(kept)
    }
    Take(id, reply) -> {
      process.send(reply, dict.get(kept, id) |> result.map(list.reverse))
      actor.continue(dict.delete(kept, id))
    }
  }
}

/// Keep a new box, it is not kept if a box in memory has the same name.
pub fn add(memory: Memory, box: Box) -> Bool {
  process.call(memory, 5000, Add(box, _))
}

/// The box after an event, `change` is the change the event merged.
pub fn record(memory: Memory, box: Box, change: Option(String)) -> Nil {
  process.send(memory, Record(box, change))
}

/// The latest state of a box, an error if it is not in memory.
pub fn get(memory: Memory, id: String) -> Result(Box, Nil) {
  process.call(memory, 5000, Get(id, _))
}

/// Whether the box in memory merged the change.
pub fn merged(memory: Memory, id: String, change: String) -> Bool {
  process.call(memory, 5000, Merged(id, change, _))
}

/// The latest state of every named box in memory, in order of name.
pub fn named(memory: Memory) -> List(Box) {
  process.call(memory, 5000, Named)
}

/// Remove a box from memory, returning its events oldest first.
pub fn take(memory: Memory, id: String) -> Result(Events, Nil) {
  process.call(memory, 5000, Take(id, _))
}
