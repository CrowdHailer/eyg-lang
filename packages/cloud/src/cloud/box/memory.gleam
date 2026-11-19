//// Boxes that are only kept in memory, as blobs are in the memory blob store.
//// A box that is only in memory is lost when the service stops.

import cloud/data/boxes.{type Box}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor

/// The state of a box after each of its events, newest first.
pub type Events =
  List(Box)

pub opaque type Message {
  Add(box: Box, reply: Subject(Bool))
  Record(box: Box, reply: Subject(Bool))
  Get(name: String, reply: Subject(Result(Box, Nil)))
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
        False -> actor.continue(dict.insert(kept, box.name, [box]))
      }
    }
    // An event is only recorded with the next sequence for the box,
    // so two changes made from the same root cannot both be recorded.
    Record(box, reply) ->
      case dict.get(kept, box.name) {
        Ok([latest, ..] as events) if box.sequence == latest.sequence + 1 -> {
          process.send(reply, True)
          actor.continue(dict.insert(kept, box.name, [box, ..events]))
        }
        _ -> {
          process.send(reply, False)
          actor.continue(kept)
        }
      }
    Get(name, reply) -> {
      process.send(reply, case dict.get(kept, name) {
        Ok([box, ..]) -> Ok(box)
        _ -> Error(Nil)
      })
      actor.continue(kept)
    }
  }
}

/// Keep a new box, it is not kept if a box in memory has the same name.
pub fn add(memory: Memory, box: Box) -> Bool {
  process.call(memory, 5000, Add(box, _))
}

/// Record the box after its next event, false if the box is not in memory or the sequence is not the next.
pub fn record(memory: Memory, box: Box) -> Bool {
  process.call(memory, 5000, Record(box, _))
}

/// The latest state of a box, an error if it is not in memory.
pub fn get(memory: Memory, name: String) -> Result(Box, Nil) {
  process.call(memory, 5000, Get(name, _))
}
