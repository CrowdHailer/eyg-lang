//// A box is a named file system that only moves to a root where all the EYG modules type check.
////
//// A box is kept in memory, see `box/memory`, until a session is made in it.
//// Then it is made durable, its events are recorded in Postgres and every later event is recorded there.

import cloud/apex/context.{type Context, type Open, Context, Open}
import cloud/beam/execute
import cloud/box/fs
import cloud/box/memory
import cloud/data/boxes.{type Box, Box}
import cloud/data/db
import cloud/file_system
import cloud/registry
import gleam/list
import gleam/option.{Some}
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

pub fn latest(context: Context, name: String) -> Result(Box, Reason) {
  use <- result.lazy_or(
    memory.get(context.memory, name) |> result.replace_error(Missing),
  )
  case query(boxes.latest(name), context) {
    Ok([box]) -> Ok(box)
    Ok(_) -> Error(Missing)
    Error(reason) -> Error(reason)
  }
}

/// Record a box in Postgres if it is only in memory, it is durable from then on.
/// A box is made durable when the first session is made in it.
pub fn durable(context: Context, name: String) -> Result(Nil, Reason) {
  use box <- result.try(latest(context, name))
  // The box's process records its events, so none are recorded while it is moved.
  registry.lookup(context.boxes, name, fn() {
    registry.serve(Open(box, check.empty()))
  })
  |> registry.call(600_000, fn(open) {
    case memory.take(context.memory, name) {
      Error(Nil) -> #(open, Ok(Nil))
      Ok(events) -> #(open, save(context, events))
    }
  })
}

fn save(context: Context, events: memory.Events) {
  db.transaction(context.db, fn(connection) {
    let context = Context(..context, db: connection)
    list.try_each(events, fn(box) { query(boxes.record(box), context) })
  })
  |> result.map_error(fn(error) {
    case error {
      pog.TransactionRolledBack(reason) -> reason
      pog.TransactionQueryError(reason) -> Failed(string.inspect(reason))
    }
  })
}

pub fn create(context: Context, name: String) -> Result(Box, Reason) {
  use root <- result.try(
    execute.files(file_system.empty(), context.state)
    |> result.map_error(Failed),
  )
  start(context, Box(name, 1, root))
}

/// The new box starts at the current root of the original.
pub fn clone(context: Context, from: Box, name: String) -> Result(Box, Reason) {
  start(context, Box(name, 1, from.root))
}

// A new box is kept in memory, a name is taken if a box in Postgres or in memory has it.
fn start(context: Context, box: Box) {
  use saved <- result.try(query(boxes.latest(box.name), context))
  case saved == [] && memory.add(context.memory, box) {
    True -> Ok(box)
    False -> Error(Taken)
  }
}

/// Make a change to the files in a box, the effect returns the new root.
pub fn change(
  context: Context,
  name: String,
  effect: fn(v1.Cid) -> mfs.Effect(Result(v1.Cid, simplifile.FileError)),
) -> Result(Box, Reason) {
  use box <- result.try(latest(context, name))
  case execute.files(effect(box.root), context.state) {
    Ok(Ok(root)) -> merge(context, name, box.root, root)
    Ok(Error(reason)) -> Error(Invalid([simplifile.describe_error(reason)]))
    Error(reason) -> Error(Failed(reason))
  }
}

/// Merge the changes from `base` to `ours` into the box.
///
/// Each box has one process that merges changes one at a time,
/// changes are made away from it and it only merges, type checks and records them.
pub fn merge(
  context: Context,
  name: String,
  base: v1.Cid,
  ours: v1.Cid,
) -> Result(Box, Reason) {
  use box <- result.try(latest(context, name))
  registry.lookup(context.boxes, name, fn() {
    registry.serve(Open(box, check.empty()))
  })
  |> registry.call(600_000, fn(open) {
    case commit(context, open, base, ours) {
      Ok(open) -> #(open, Ok(open.box))
      Error(reason) -> #(open, Error(reason))
    }
  })
}

fn commit(context: Context, open: Open, base, ours) {
  let Open(box, index) = open
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
        execute.files(fs.change(index, merged, context.state), context.state)
      {
        Ok(#([], index, _)) -> Ok(index)
        Ok(#(errors, _, _)) -> Error(Invalid(errors))
        Error(reason) -> Error(Failed(reason))
      }
  })
  use box <- result.map(case merged == box.root {
    True -> Ok(box)
    False -> record(context, Box(box.name, box.sequence + 1, merged))
  })
  Open(box, index)
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
fn record(context: Context, box: Box) {
  case memory.get(context.memory, box.name) {
    Ok(_) ->
      case memory.record(context.memory, box) {
        True -> Ok(box)
        False -> Error(Taken)
      }
    Error(Nil) ->
      case query(boxes.record(box), context) {
        Ok([box]) -> Ok(box)
        Ok(_) -> Error(Taken)
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
