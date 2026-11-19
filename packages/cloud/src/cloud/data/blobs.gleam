//// Blobs are the blocks of every file system, stored under their content identifier.
////
//// A blob store is a process and is passed around as its subject, not as a record of functions.
//// Every store handles the same messages, so code using blobs does not know where they are kept.

import bucket
import bucket/get_object
import bucket/put_object
import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/httpc
import gleam/otp/actor
import gleam/result
import gleam/string

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

/// Blobs are objects in a bucket, requests are made one at a time.
pub fn s3(
  credentials: bucket.Credentials,
  bucket: String,
) -> actor.StartResult(Blobs) {
  actor.new(Nil)
  |> actor.on_message(fn(_, message) {
    case message {
      Get(key, reply) ->
        process.send(reply, {
          use response <- result.try(
            get_object.request(bucket:, key:)
            |> get_object.build(credentials)
            |> send,
          )
          case get_object.response(response) {
            Ok(get_object.Found(body)) -> Ok(body)
            Ok(get_object.NotFound) -> Error("No blob " <> key)
            Error(reason) -> Error(string.inspect(reason))
          }
        })
      Put(key, body, reply) ->
        process.send(reply, {
          use response <- result.try(
            put_object.request(bucket:, key:, body:)
            |> put_object.build(credentials)
            |> send,
          )
          put_object.response(response)
          |> result.replace(Nil)
          |> result.map_error(string.inspect)
        })
    }
    actor.continue(Nil)
  })
  |> actor.start
}

fn send(request) {
  httpc.send_bits(request) |> result.map_error(string.inspect)
}
