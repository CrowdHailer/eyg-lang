//// A box is a file system that only moves to a root where all the EYG modules type check.
//// A box with a name is shared, a box without one is transient.
////
//// A box is kept in memory, see `box/memory`, until a session is made in it.
//// Then it is made durable, its events are recorded in Postgres and every later event is recorded there.

import cloud/apex/context.{type Context, type Open, Context, Open}
import cloud/beam/execute
import cloud/box/fs
import cloud/box/memory
import cloud/data/boxes.{type Box, Box}
import cloud/data/db
import cloud/data/secrets
import cloud/file_system
import cloud/registry
import gleam/bit_array
import gleam/crypto
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import multiformats/cid/v1
import pog
import simplifile
import unixfs/check
import unixfs/mfs

pub type Reason {
  Missing
  /// The box name is taken.
  Taken
  /// Files changed by this change were also changed since its base.
  Conflict(paths: List(String))
  Invalid(List(String))
  Failed(String)
}

pub fn latest(context: Context, id: String) -> Result(Box, Reason) {
  use <- result.lazy_or(
    memory.get(context.memory, id) |> result.replace_error(Missing),
  )
  case query(boxes.latest(id), context) {
    Ok([box]) -> Ok(box)
    Ok(_) -> Error(Missing)
    Error(reason) -> Error(reason)
  }
}

/// Record a box in Postgres if it is only in memory, it is durable from then on.
/// A box is made durable when the first session is made in it.
pub fn durable(context: Context, id: String) -> Result(Nil, Reason) {
  use box <- result.try(latest(context, id))
  // The box's process records its events, so none are recorded while it is moved.
  registry.lookup(context.boxes, id, fn() {
    registry.serve(Open(box, check.empty()))
  })
  |> registry.call(600_000, fn(open) {
    case memory.take(context.memory, id) {
      Error(Nil) -> #(open, Ok(Nil))
      Ok(#(events, secrets)) -> #(open, save(context, id, events, secrets))
    }
  })
}

fn save(context: Context, id, events: memory.Events, kept) {
  let name = case events {
    [#(box, _), ..] -> box.name
    [] -> None
  }
  db.transaction(context.db, fn(connection) {
    let context = Context(..context, db: connection)
    use _ <- result.try(query(boxes.insert(id, name), context))
    use _ <- result.try(
      list.try_each(events, fn(event) {
        let #(box, change) = event
        query(boxes.record(box, change), context)
      }),
    )
    dict.to_list(kept)
    |> list.try_each(fn(secret) {
      query(secrets.set(id, secret.0, secret.1), context)
    })
  })
  |> result.map_error(fn(error) {
    case error {
      pog.TransactionRolledBack(reason) -> reason
      pog.TransactionQueryError(reason) -> Failed(string.inspect(reason))
    }
  })
}

pub fn create(context: Context, name: Option(String)) -> Result(Box, Reason) {
  use root <- result.try(
    execute.files(file_system.empty(), context.state)
    |> result.map_error(Failed),
  )
  start(context, name, root)
}

/// The new box starts at the current root of the original, with a copy of its secrets.
pub fn clone(
  context: Context,
  from: Box,
  name: Option(String),
) -> Result(Box, Reason) {
  use secrets <- result.try(secrets(context, from.id))
  use box <- result.map(start(context, name, from.root))
  memory.set_secrets(context.memory, box.id, secrets)
  box
}

/// The secrets of a box by name, code in the box reads them with the Env effect.
pub fn secrets(
  context: Context,
  id: String,
) -> Result(Dict(String, String), Reason) {
  case memory.secrets(context.memory, id) {
    Ok(secrets) -> Ok(secrets)
    Error(Nil) -> query(secrets.all(id), context) |> result.map(dict.from_list)
  }
}

/// Add a secret to a box, or replace the one with the same name.
/// A name is uppercase letters, digits and underscores, as for environment variables.
pub fn set_secret(
  context: Context,
  id: String,
  name: String,
  value: String,
) -> Result(Nil, Reason) {
  let allowed = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
  case
    name != ""
    && list.all(string.to_graphemes(name), string.contains(allowed, _))
  {
    False ->
      Error(
        Invalid(["A secret name is uppercase letters, digits and underscores"]),
      )
    True -> {
      use _ <- result.try(latest(context, id))
      case memory.secrets(context.memory, id) {
        Ok(kept) ->
          Ok(memory.set_secrets(
            context.memory,
            id,
            dict.insert(kept, name, value),
          ))
        Error(Nil) ->
          query(secrets.set(id, name, value), context) |> result.replace(Nil)
      }
    }
  }
}

pub fn delete_secret(
  context: Context,
  id: String,
  name: String,
) -> Result(Nil, Reason) {
  case memory.secrets(context.memory, id) {
    Ok(kept) ->
      Ok(memory.set_secrets(context.memory, id, dict.delete(kept, name)))
    Error(Nil) ->
      query(secrets.delete(id, name), context) |> result.replace(Nil)
  }
}

/// All the named boxes, in order of name.
pub fn named(context: Context) -> Result(List(Box), Reason) {
  use saved <- result.map(query(boxes.named(), context))
  list.append(saved, memory.named(context.memory))
  |> list.sort(fn(a, b) {
    string.compare(option.unwrap(a.name, ""), option.unwrap(b.name, ""))
  })
}

// A name is lowercase letters, digits and dashes.
// A new box is kept in memory, a name is taken if a box in Postgres or in memory has it.
fn start(context, name, root) {
  let allowed = "abcdefghijklmnopqrstuvwxyz0123456789-"
  let valid = fn(name) {
    name != ""
    && list.all(string.to_graphemes(name), string.contains(allowed, _))
  }
  use Nil <- result.try(case option.map(name, valid) {
    Some(False) ->
      Error(Invalid(["A box name is lowercase letters, digits and dashes"]))
    _ -> Ok(Nil)
  })
  use saved <- result.try(query(boxes.named(), context))
  let taken = name != None && list.any(saved, fn(box: Box) { box.name == name })
  let box = Box(id(), name, 1, root)
  case !taken && memory.add(context.memory, box) {
    True -> Ok(box)
    False -> Error(Taken)
  }
}

// A random identifier in the form of a UUID.
fn id() {
  let hex =
    crypto.strong_random_bytes(16)
    |> bit_array.base16_encode
    |> string.lowercase
  [#(0, 8), #(8, 4), #(12, 4), #(16, 4), #(20, 12)]
  |> list.map(fn(part) { string.slice(hex, part.0, part.1) })
  |> string.join("-")
}

/// Make a change to the files in a box, the effect returns the new root.
pub fn change(
  context: Context,
  id: String,
  effect: fn(v1.Cid) -> mfs.Effect(Result(v1.Cid, simplifile.FileError)),
) -> Result(Box, Reason) {
  use box <- result.try(latest(context, id))
  case execute.files(effect(box.root), context.state) {
    Ok(Ok(root)) -> merge(context, id, box.root, root, None)
    Ok(Error(reason)) -> Error(Invalid([simplifile.describe_error(reason)]))
    Error(reason) -> Error(Failed(reason))
  }
}

/// Merge the changes from `base` to `ours` into the box.
/// A change with an identifier is only merged once, merging it again returns the latest box.
///
/// Each box has one process that merges changes one at a time,
/// changes are made away from it and it only merges, type checks and records them.
pub fn merge(
  context: Context,
  id: String,
  base: v1.Cid,
  ours: v1.Cid,
  change: Option(String),
) -> Result(Box, Reason) {
  use box <- result.try(latest(context, id))
  registry.lookup(context.boxes, id, fn() {
    registry.serve(Open(box, check.empty()))
  })
  |> registry.call(600_000, fn(open) {
    case commit(context, open, base, ours, change) {
      Ok(open) -> #(open, Ok(open.box))
      Error(reason) -> #(open, Error(reason))
    }
  })
}

fn commit(context: Context, open: Open, base, ours, change) {
  let Open(box, index) = open
  // A box in memory remembers the changes it merged, a durable box records them.
  use merged <- result.try(case change, memory.get(context.memory, box.id) {
    Some(change), Ok(_) -> Ok(memory.merged(context.memory, box.id, change))
    Some(change), Error(Nil) ->
      query(boxes.merged(box.id, change), context)
      |> result.map(fn(rows) { rows != [] })
    None, _ -> Ok(False)
  })
  case merged {
    True -> Ok(open)
    False -> {
      use merged <- result.try(case base == box.root {
        True -> Ok(ours)
        False ->
          case execute.files(three_way(base, ours, box.root), context.state) {
            Ok(Ok(root)) -> Ok(root)
            Ok(Error(paths)) ->
              Error(
                Conflict(
                  list.map(paths, fn(path) { "/" <> string.join(path, "/") }),
                ),
              )
            Error(reason) -> Error(Failed(reason))
          }
      })
      // Only the modules affected by the changes since the last check are checked.
      use index <- result.try(case merged == box.root {
        True -> Ok(index)
        False ->
          case
            execute.files(
              fs.change(index, merged, context.state),
              context.state,
            )
          {
            Ok(#([], index, _)) -> Ok(index)
            Ok(#(errors, _, _)) -> Error(Invalid(errors))
            Error(reason) -> Error(Failed(reason))
          }
      })
      // A change with an identifier is recorded even if it changes nothing, so it is not merged again.
      use box <- result.map(case merged == box.root && change == None {
        True -> Ok(box)
        False ->
          record(
            context,
            Box(..box, sequence: box.sequence + 1, root: merged),
            change,
          )
      })
      Open(box, index)
    }
  }
}

// Merge the change from `base` to `ours` with the change from `base` to `theirs`.
// The files both changes changed are the conflict.
fn three_way(base, ours, theirs) {
  let stored = fn(cid) { Some(mfs.Stored(cid, 0)) }
  use merged <- mfs.then(mfs.merge(stored(base), stored(ours), stored(theirs)))
  case merged {
    Ok(Some(root)) -> mfs.Done(Ok(root.cid))
    _ -> {
      use ours <- mfs.then(mfs.diff(base, ours))
      use theirs <- mfs.then(mfs.diff(base, theirs))
      mfs.Done(Error(list.filter(ours, list.contains(theirs, _))))
    }
  }
}

// A box in memory keeps its events there, a durable box records them in Postgres.
fn record(context: Context, box: Box, change) {
  case memory.get(context.memory, box.id) {
    Ok(_) -> {
      memory.record(context.memory, box, change)
      Ok(box)
    }
    Error(Nil) ->
      case query(boxes.record(box, change), context) {
        Ok([box]) -> Ok(box)
        // Only the box's process records its events.
        Ok(_) -> Error(Failed("the box was changed by another process"))
        Error(reason) -> Error(reason)
      }
  }
}

fn query(query, context: Context) {
  case db.execute(query, context.db) {
    Ok(pog.Returned(rows:, ..)) -> Ok(rows)
    Error(reason) -> Error(Failed(string.inspect(reason)))
  }
}
