//// Blobs are the blocks of every file system, stored under their content identifier.
////
//// A blob store is a process and is passed around as its subject, not as a record of functions.
//// Every store handles the same messages, so code using blobs does not know where they are kept.

import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/result

pub type Message {
  Get(key: String, reply: Subject(Result(BitArray, String)))
  Put(key: String, blob: BitArray, reply: Subject(Result(Nil, String)))
}

pub type Blobs =
  Subject(Message)

pub fn get(blobs: Blobs, key: String) -> Result(BitArray, String) {
  process.call(blobs, 30_000, Get(key, _))
}

pub fn put(blobs: Blobs, key: String, blob: BitArray) -> Result(Nil, String) {
  process.call(blobs, 30_000, Put(key, blob, _))
}

pub fn start() -> actor.StartResult(Blobs) {
  actor.new(dict.new())
  |> actor.on_message(fn(blobs, message) {
    case message {
      Get(key, reply) -> {
        dict.get(blobs, key)
        |> result.replace_error("No blob " <> key)
        |> process.send(reply, _)
        actor.continue(blobs)
      }
      Put(key, blob, reply) -> {
        process.send(reply, Ok(Nil))
        actor.continue(dict.insert(blobs, key, blob))
      }
    }
  })
  |> actor.start
}
