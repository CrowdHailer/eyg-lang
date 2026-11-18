//// Blobs are the blocks of every file system, stored under their content identifier.
////
//// A blob store is a process and is passed around as its subject, not as a record of functions.
//// Every store handles the same messages, so code using blobs does not know where they are kept.

import bucket
import bucket/get_object
import bucket/list_objects
import bucket/put_object
import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/httpc
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/result
import gleam/string

pub type Message {
  Get(key: String, reply: Subject(Result(BitArray, String)))
  Put(key: String, blob: BitArray, reply: Subject(Result(Nil, String)))
  /// A blob that is already stored, read by another process, for a store to keep in memory.
  Keep(key: String, blob: BitArray)
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
      Keep(key, blob) -> actor.continue(dict.insert(blobs, key, blob))
    }
  })
  |> actor.start
}

/// Blobs are objects in a bucket, requests are made one at a time.
/// A blob never changes, so each one read or written is kept in memory and only read from the bucket once.
/// A request to the bucket takes much longer than one to Postgres and reading a file system reads its blocks one
/// after another, so when the store starts every blob in the bucket is read, by several processes, and kept.
pub fn s3(
  credentials: bucket.Credentials,
  bucket: String,
) -> actor.StartResult(Blobs) {
  let started =
    actor.new(dict.new())
    |> actor.on_message(fn(kept, message) {
      case message {
        Get(key, reply) ->
          case dict.get(kept, key) {
            Ok(blob) -> {
              process.send(reply, Ok(blob))
              actor.continue(kept)
            }
            Error(Nil) -> {
              let read = read(credentials, bucket, key)
              process.send(reply, read)
              case read {
                Ok(blob) -> actor.continue(dict.insert(kept, key, blob))
                Error(_) -> actor.continue(kept)
              }
            }
          }
        Put(key, body, reply) -> {
          let written = {
            use response <- result.try(
              put_object.request(bucket:, key:, body:)
              |> put_object.build(credentials)
              |> send,
            )
            put_object.response(response)
            |> result.replace(Nil)
            |> result.map_error(string.inspect)
          }
          process.send(reply, written)
          case written {
            Ok(Nil) -> actor.continue(dict.insert(kept, key, body))
            Error(_) -> actor.continue(kept)
          }
        }
        Keep(key, blob) -> actor.continue(dict.insert(kept, key, blob))
      }
    })
    |> actor.start
  use started <- result.map(started)
  process.spawn_unlinked(fn() { read_all(credentials, bucket, started.data) })
  started
}

fn read(credentials, bucket, key) {
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
}

// Read every blob in the bucket and give them to the store to keep, sixteen at a time.
fn read_all(credentials, bucket, store) {
  let keys = keys(credentials, bucket, None, [])
  list.index_map(keys, fn(key, i) { #(i % 16, key) })
  |> list.group(fn(entry) { entry.0 })
  |> dict.each(fn(_, share) {
    process.spawn_unlinked(fn() {
      list.each(share, fn(entry) {
        case read(credentials, bucket, entry.1) {
          Ok(blob) -> process.send(store, Keep(entry.1, blob))
          Error(_) -> Nil
        }
      })
    })
  })
}

// The key of every object in the bucket, a page at a time.
fn keys(credentials, bucket, after, acc) {
  let request = list_objects.request(bucket)
  let request = case after {
    Some(key) -> list_objects.start_after(request, key)
    None -> request
  }
  let page = {
    use response <- result.try(list_objects.build(request, credentials) |> send)
    list_objects.response(response) |> result.map_error(string.inspect)
  }
  case page {
    Ok(list_objects.ListObjectsResult(is_truncated:, contents:)) -> {
      let acc =
        list.fold(contents, acc, fn(acc, object) { [object.key, ..acc] })
      case is_truncated, list.last(contents) {
        True, Ok(last) -> keys(credentials, bucket, Some(last.key), acc)
        _, _ -> acc
      }
    }
    Error(_) -> acc
  }
}

fn send(request) {
  httpc.send_bits(request) |> result.map_error(string.inspect)
}
