//// Boxes that are only kept in memory, as blobs are in the memory blob store.
//// A box is kept here until a session is made in it, then its events are recorded in Postgres,
//// see `box.durable`.
//// A box that no session was made in is lost when the service stops.

import cloud/data/boxes.{type Box}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result

/// The state of a box after each of its events, with the change each event merged.
pub type Events =
  List(#(Box, Option(String)))

pub opaque type Message {
  Add(box: Box, reply: Subject(Bool))
  Record(box: Box, change: Option(String), reply: Subject(Bool))
  Get(name: String, reply: Subject(Result(Box, Nil)))
  Merged(name: String, change: String, reply: Subject(Bool))
  Take(name: String, reply: Subject(Result(Events, Nil)))
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
      let taken = dict.has_key(kept, box.name)
      process.send(reply, !taken)
      case taken {
        True -> actor.continue(kept)
        False -> actor.continue(dict.insert(kept, box.name, [#(box, None)]))
      }
    }
    // An event is only recorded with the next sequence for the box,
    // so two changes made from the same root cannot both be recorded.
    Record(box, change, reply) ->
      case dict.get(kept, box.name) {
        Ok([#(latest, _), ..] as events)
          if box.sequence == latest.sequence + 1
        -> {
          process.send(reply, True)
          actor.continue(
            dict.insert(kept, box.name, [#(box, change), ..events]),
          )
        }
        _ -> {
          process.send(reply, False)
          actor.continue(kept)
        }
      }
    Get(name, reply) -> {
      process.send(reply, case dict.get(kept, name) {
        Ok([#(box, _), ..]) -> Ok(box)
        _ -> Error(Nil)
      })
      actor.continue(kept)
    }
    Merged(name, change, reply) -> {
      let events = dict.get(kept, name) |> result.unwrap([])
      process.send(
        reply,
        list.any(events, fn(event) { event.1 == Some(change) }),
      )
      actor.continue(kept)
    }
    Take(name, reply) -> {
      process.send(reply, case dict.get(kept, name) {
        Ok(events) -> Ok(list.reverse(events))
        Error(Nil) -> Error(Nil)
      })
      actor.continue(dict.delete(kept, name))
    }
  }
}

/// Keep a new box, it is not kept if a box in memory has the same name.
pub fn add(memory: Memory, box: Box) -> Bool {
  process.call(memory, 5000, Add(box, _))
}

/// Record the box after its next event, false if the box is not in memory or the sequence is not the next.
/// `change` is the change the event merged.
pub fn record(memory: Memory, box: Box, change: Option(String)) -> Bool {
  process.call(memory, 5000, Record(box, change, _))
}

/// The latest state of a box, an error if it is not in memory.
pub fn get(memory: Memory, name: String) -> Result(Box, Nil) {
  process.call(memory, 5000, Get(name, _))
}

/// Whether the box in memory merged the change.
pub fn merged(memory: Memory, name: String, change: String) -> Bool {
  process.call(memory, 5000, Merged(name, change, _))
}

/// Remove a box from memory, returning its events oldest first.
pub fn take(memory: Memory, name: String) -> Result(Events, Nil) {
  process.call(memory, 5000, Take(name, _))
}
