//// The workspace's shared file system.
////
//// Every session in a workspace reads and writes one content addressed file system,
//// built with the `unixfs/mfs` module on an in memory block store.
//// Paths are absolute, policies decide which paths a channel can read and write.
//// Every change is reported to subscribers with who made it, so sessions can be told
//// when a file they read has changed.

import filepath
import gleam/bit_array
import gleam/crypto
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import gleam/string
import multiformats/cid/v1
import multiformats/hashes
import simplifile
import touch_grass/file_system/read_directory
import unixfs
import unixfs/mfs

/// A change to the file system and the session that made it.
pub type Change {
  Change(path: String, by: String)
}

pub type Message {
  Read(path: String, reply: Subject(Result(BitArray, String)))
  ReadDirectory(
    path: String,
    reply: Subject(Result(List(#(String, read_directory.Entry)), String)),
  )
  Update(
    operation: Operation,
    path: String,
    by: String,
    reply: Subject(Result(Nil, String)),
  )
  Subscribe(Subject(Change))
}

pub type Operation {
  Write(BitArray)
  Append(BitArray)
  Delete
  MakeDirectory
}

type State {
  State(
    blocks: Dict(String, BitArray),
    root: mfs.Entry,
    root_cid: v1.Cid,
    subscribers: List(Subject(Change)),
  )
}

/// Start a file system with the files and directories under `seed` on the host.
pub fn start(seed: Option(String)) -> Result(Subject(Message), String) {
  let state = store_root(dict.new(), mfs.Directory([]), [])
  use state <- result.try(case seed {
    Some(directory) -> copy_in(state, directory, "/")
    None -> Ok(state)
  })
  actor.new(state)
  |> actor.on_message(handle)
  |> actor.start
  |> result.map(fn(started) { started.data })
  |> result.map_error(string.inspect)
}

fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Read(path:, reply:) -> {
      let #(result, _) =
        run(mfs.read(state.root_cid, segments(path)), state.blocks)
      process.send(reply, result |> result.map_error(describe(path, _)))
      actor.continue(state)
    }
    ReadDirectory(path:, reply:) -> {
      let #(result, _) =
        run(mfs.read_directory(state.root_cid, segments(path)), state.blocks)
      result
      |> result.map(list.map(_, entry))
      |> result.map_error(describe(path, _))
      |> process.send(reply, _)
      actor.continue(state)
    }
    Update(operation:, path:, by:, reply:) ->
      case update(state, operation, path) {
        Ok(state) -> {
          process.send(reply, Ok(Nil))
          let change = Change(path: normalize(path), by:)
          list.each(state.subscribers, process.send(_, change))
          actor.continue(state)
        }
        Error(reason) -> {
          process.send(reply, Error(reason))
          actor.continue(state)
        }
      }
    Subscribe(subscriber) ->
      actor.continue(
        State(..state, subscribers: [subscriber, ..state.subscribers]),
      )
  }
}

fn update(state: State, operation, path) -> Result(State, String) {
  let parts = segments(path)
  let root = Some(state.root)
  let effect = case operation {
    Write(contents) -> mfs.write(root, parts, contents)
    Append(contents) -> mfs.append(root, parts, contents)
    Delete -> mfs.delete(root, parts)
    MakeDirectory -> mfs.make_directory(root, parts)
  }
  let #(result, blocks) = run(effect, state.blocks)
  case result {
    Ok(root) -> Ok(store_root(blocks, root, state.subscribers))
    Error(reason) -> Error(describe(path, reason))
  }
}

fn store_root(blocks, root, subscribers) {
  let #(cid, blocks) = put(blocks, root)
  State(blocks:, root:, root_cid: cid, subscribers:)
}

/// Interpret file system effects against the block store.
fn run(
  effect: mfs.Effect(t),
  blocks: Dict(String, BitArray),
) -> #(Result(t, simplifile.FileError), Dict(String, BitArray)) {
  case effect {
    mfs.Done(result) -> #(result, blocks)
    mfs.Put(entry, resume) -> {
      let #(cid, blocks) = put(blocks, entry)
      run(resume(Ok(mfs.Stored(cid, size(blocks, entry, cid)))), blocks)
    }
    mfs.Get(cid, resume) -> run(resume(get(blocks, cid)), blocks)
  }
}

fn put(blocks, entry) {
  let #(code, block) = case entry {
    mfs.File(contents) -> #(unixfs.raw_code, contents)
    mfs.Directory(links) -> {
      let assert Ok(block) = unixfs.encode_directory(links)
      #(unixfs.dag_pb_code, block)
    }
  }
  let cid =
    v1.Cid(
      code,
      hashes.Multihash(hashes.Sha256, crypto.hash(crypto.Sha256, block)),
    )
  #(cid, dict.insert(blocks, v1.to_string(cid), block))
}

/// Links record the cumulative size of everything below them.
fn size(blocks, entry, cid) {
  let own =
    dict.get(blocks, v1.to_string(cid))
    |> result.map(bit_array.byte_size)
    |> result.unwrap(0)
  case entry {
    mfs.File(_) -> own
    mfs.Directory(links) ->
      list.fold(links, own, fn(total, l) { total + l.size })
  }
}

fn get(blocks, cid: v1.Cid) -> Result(mfs.Entry, simplifile.FileError) {
  case dict.get(blocks, v1.to_string(cid)) {
    Error(Nil) -> Error(simplifile.Enoent)
    Ok(block) ->
      case is_raw(cid) {
        True -> Ok(mfs.File(block))
        False ->
          unixfs.decode_directory(block)
          |> result.map(mfs.Directory)
          |> result.replace_error(simplifile.Eio)
      }
  }
}

fn entry(link: unixfs.Link) {
  case is_raw(link.cid) {
    True -> #(link.name, read_directory.File(link.size))
    False -> #(link.name, read_directory.Directory)
  }
}

/// Copy a directory on the host into the file system.
fn copy_in(state: State, host: String, path: String) -> Result(State, String) {
  use names <- result.try(
    simplifile.read_directory(host)
    |> result.map_error(simplifile.describe_error),
  )
  list.try_fold(list.sort(names, string.compare), state, fn(state, name) {
    let source = filepath.join(host, name)
    let target = filepath.join(path, name)
    case simplifile.is_directory(source) {
      Ok(True) -> {
        use state <- result.try(update(state, MakeDirectory, target))
        copy_in(state, source, target)
      }
      _ -> {
        use contents <- result.try(
          simplifile.read_bits(source)
          |> result.map_error(simplifile.describe_error),
        )
        update(state, Write(contents), target)
      }
    }
  })
}

/// Make a path absolute and remove `.` and `..` segments.
pub fn normalize(path: String) -> String {
  case filepath.expand(filepath.join("/", path)) {
    Ok(path) -> path
    Error(Nil) -> "/"
  }
}

fn segments(path) {
  normalize(path)
  |> string.split("/")
  |> list.filter(fn(part) { part != "" })
}

fn describe(path, reason) {
  path <> ": " <> simplifile.describe_error(reason)
}

pub fn call(files: Subject(Message), make) {
  process.call(files, 5000, make)
}

/// Read part of a file, as the `ReadFile` effect does.
pub fn slice(bytes: BitArray, offset: Int, limit: Int) -> BitArray {
  let size = bit_array.byte_size(bytes)
  let offset = int.clamp(offset, 0, size)
  let limit = int.clamp(limit, 0, size - offset)
  bit_array.slice(bytes, offset, limit) |> result.unwrap(<<>>)
}

fn is_raw(cid: v1.Cid) {
  let v1.Cid(codec, _) = cid
  codec == unixfs.raw_code
}
