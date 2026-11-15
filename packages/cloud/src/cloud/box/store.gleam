//// Versioned snapshots. Acknowledgement follows a synced atomic replacement.

import cloud/beam/file_system
import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import multiformats/cid/v1
import simplifile
import unixfs
import unixfs/mfs

pub type Snapshot {
  Snapshot(files: file_system.State, history: List(v1.Cid))
}

@external(erlang, "cloud_store_ffi", "atomic_write")
pub fn atomic_write(path: String, bytes: BitArray) -> Result(Nil, String)

pub fn save(path: String, snapshot: Snapshot) {
  encode(snapshot)
  |> json.to_string
  |> bit_array.from_string
  |> atomic_write(path, _)
}

pub fn load(path: String) {
  use text <- result.try(
    simplifile.read(path) |> result.map_error(simplifile.describe_error),
  )
  use snapshot <- result.try(
    json.parse(text, decoder()) |> result.replace_error("Invalid box snapshot"),
  )
  use _ <- result.try(
    list.try_each(dict.to_list(snapshot.files.blocks), fn(pair) {
      case mfs.identify(pair.1).cid == pair.0 {
        True -> Ok(Nil)
        False -> Error("Corrupt content block")
      }
    }),
  )
  use _ <- result.try(
    list.try_each([snapshot.files.root, ..snapshot.history], fn(root) {
      case dict.get(snapshot.files.blocks, root) {
        Ok(mfs.Directory(_)) -> Ok(Nil)
        _ -> Error("Missing snapshot root")
      }
    }),
  )
  Ok(snapshot)
}

fn encode(snapshot: Snapshot) {
  json.object([
    #("format", json.int(1)),
    #("root", json.string(v1.to_string(snapshot.files.root))),
    #(
      "history",
      json.array(snapshot.history, fn(cid) { json.string(v1.to_string(cid)) }),
    ),
    #(
      "blocks",
      json.array(dict.to_list(snapshot.files.blocks), fn(pair) {
        json.object([
          #("cid", json.string(v1.to_string(pair.0))),
          #("entry", case pair.1 {
            mfs.File(bytes) ->
              json.object([
                #("file", json.string(bit_array.base64_encode(bytes, True))),
              ])
            mfs.Directory(links) ->
              json.object([
                #(
                  "directory",
                  json.array(links, fn(link) {
                    json.object([
                      #("name", json.string(link.name)),
                      #("cid", json.string(v1.to_string(link.cid))),
                      #("size", json.int(link.size)),
                    ])
                  }),
                ),
              ])
          }),
        ])
      }),
    ),
  ])
}

pub fn cid_decoder() {
  use text <- decode.then(decode.string)
  case v1.from_string(text) {
    Ok(#(cid, <<>>)) -> decode.success(cid)
    _ -> decode.failure(mfs.identify(mfs.Directory([])).cid, "CID")
  }
}

fn entry_decoder() {
  decode.one_of(file_decoder(), [directory_decoder()])
}

fn file_decoder() {
  use text <- decode.field("file", decode.string)
  case bit_array.base64_decode(text) {
    Ok(bytes) -> decode.success(mfs.File(bytes))
    Error(_) -> decode.failure(mfs.File(<<>>), "base64")
  }
}

fn directory_decoder() {
  use links <- decode.field(
    "directory",
    decode.list({
      use name <- decode.field("name", decode.string)
      use cid <- decode.field("cid", cid_decoder())
      use size <- decode.field("size", decode.int)
      decode.success(unixfs.Link(cid, name, size))
    }),
  )
  decode.success(mfs.Directory(links))
}

fn decoder() {
  use format <- decode.field("format", decode.int)
  use root <- decode.field("root", cid_decoder())
  use history <- decode.field("history", decode.list(cid_decoder()))
  use blocks <- decode.field(
    "blocks",
    decode.list({
      use cid <- decode.field("cid", cid_decoder())
      use entry <- decode.field("entry", entry_decoder())
      decode.success(#(cid, entry))
    }),
  )
  let snapshot =
    Snapshot(file_system.State(root, dict.from_list(blocks)), history)
  case format {
    1 -> decode.success(snapshot)
    _ -> decode.failure(snapshot, "snapshot format 1")
  }
}
