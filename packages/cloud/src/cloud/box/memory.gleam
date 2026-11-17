//// Boxes that are only kept in memory, as blobs are in the memory blob store.
//// A box is kept here until a session is made in it, then its events and secrets are recorded in Postgres,
//// see `box.durable`.
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

type Kept {
  Kept(events: Events, secrets: Dict(String, String))
}

pub opaque type Message {
  Add(box: Box, reply: Subject(Bool))
  Record(box: Box, change: Option(String))
  Get(id: String, reply: Subject(Result(Box, Nil)))
  Merged(id: String, change: String, reply: Subject(Bool))
  Named(reply: Subject(List(Box)))
  Secrets(id: String, reply: Subject(Result(Dict(String, String), Nil)))
  SetSecrets(id: String, secrets: Dict(String, String))
  Take(id: String, reply: Subject(Result(#(Events, Dict(String, String)), Nil)))
}

pub type Memory =
  Subject(Message)

pub fn start() -> actor.StartResult(Memory) {
  actor.new(dict.new())
  |> actor.on_message(handle)
  |> actor.start
}

fn handle(kept: Dict(String, Kept), message) {
  case message {
    Add(box, reply) -> {
      let taken =
        box.name != option.None
        && list.any(dict.values(kept), fn(kept) {
          case kept.events {
            [#(latest, _), ..] -> latest.name == box.name
            [] -> False
          }
        })
      process.send(reply, !taken)
      case taken {
        True -> actor.continue(kept)
        False ->
          actor.continue(dict.insert(
            kept,
            box.id,
            Kept([#(box, option.None)], dict.new()),
          ))
      }
    }
    Record(box, change) ->
      case dict.get(kept, box.id) {
        Ok(Kept(events, secrets)) ->
          actor.continue(dict.insert(
            kept,
            box.id,
            Kept([#(box, change), ..events], secrets),
          ))
        Error(Nil) -> actor.continue(kept)
      }
    Get(id, reply) -> {
      process.send(reply, case dict.get(kept, id) {
        Ok(Kept([#(box, _), ..], _)) -> Ok(box)
        _ -> Error(Nil)
      })
      actor.continue(kept)
    }
    Merged(id, change, reply) -> {
      let events = case dict.get(kept, id) {
        Ok(kept) -> kept.events
        Error(Nil) -> []
      }
      process.send(
        reply,
        list.any(events, fn(event) { event.1 == Some(change) }),
      )
      actor.continue(kept)
    }
    Named(reply) -> {
      dict.values(kept)
      |> list.filter_map(fn(kept) {
        case kept.events {
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
    Secrets(id, reply) -> {
      process.send(
        reply,
        dict.get(kept, id) |> result.map(fn(kept) { kept.secrets }),
      )
      actor.continue(kept)
    }
    SetSecrets(id, secrets) ->
      case dict.get(kept, id) {
        Ok(Kept(events, _)) ->
          actor.continue(dict.insert(kept, id, Kept(events, secrets)))
        Error(Nil) -> actor.continue(kept)
      }
    Take(id, reply) -> {
      process.send(reply, case dict.get(kept, id) {
        Ok(Kept(events, secrets)) -> Ok(#(list.reverse(events), secrets))
        Error(Nil) -> Error(Nil)
      })
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

/// The secrets of a box in memory.
pub fn secrets(
  memory: Memory,
  id: String,
) -> Result(Dict(String, String), Nil) {
  process.call(memory, 5000, Secrets(id, _))
}

/// Replace the secrets of a box in memory.
pub fn set_secrets(
  memory: Memory,
  id: String,
  secrets: Dict(String, String),
) -> Nil {
  process.send(memory, SetSecrets(id, secrets))
}

/// Remove a box from memory, returning its events oldest first and its secrets.
pub fn take(
  memory: Memory,
  id: String,
) -> Result(#(Events, Dict(String, String)), Nil) {
  process.call(memory, 5000, Take(id, _))
}
