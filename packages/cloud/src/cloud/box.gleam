//// A box is a file system that only moves to a root where all the EYG modules type check.
//// A box with a name is shared, a box without one is transient.

import cloud/apex/context.{type Context}
import cloud/beam/execute
import cloud/box/fs
import cloud/data/boxes.{type Box, Box}
import cloud/data/db
import cloud/file_system
import cloud/registry
import gleam/list
import gleam/option.{type Option, Some}
import gleam/result
import gleam/string
import multiformats/cid/v1
import pog
import simplifile
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
  case query(boxes.latest(id), context) {
    Ok([box]) -> Ok(box)
    Ok(_) -> Error(Missing)
    Error(reason) -> Error(reason)
  }
}

pub fn create(context: Context, name: Option(String)) -> Result(Box, Reason) {
  use root <- result.try(
    execute.files(file_system.empty(), context.state)
    |> result.map_error(Failed),
  )
  start(context, name, root)
}

/// The new box starts at the current root of the original.
pub fn clone(
  context: Context,
  from: Box,
  name: Option(String),
) -> Result(Box, Reason) {
  start(context, name, from.root)
}

/// All the named boxes, in order of name.
pub fn named(context: Context) -> Result(List(Box), Reason) {
  query(boxes.named(), context)
}

fn start(context, name, root) {
  case query(boxes.create(name, root), context) {
    Ok([box]) -> Ok(box)
    Ok(_) -> Error(Taken)
    Error(reason) -> Error(reason)
  }
}

/// Make a change to the files in a box, the effect returns the new root.
pub fn change(
  context: Context,
  id: String,
  effect: fn(v1.Cid) -> mfs.Effect(Result(v1.Cid, simplifile.FileError)),
) -> Result(Box, Reason) {
  use box <- result.try(latest(context, id))
  case execute.files(effect(box.root), context.state) {
    Ok(Ok(root)) -> merge(context, id, box.root, root)
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
  id: String,
  base: v1.Cid,
  ours: v1.Cid,
) -> Result(Box, Reason) {
  use box <- result.try(latest(context, id))
  registry.lookup(context.boxes, id, fn() { registry.serve(box) })
  |> registry.call(600_000, fn(box) {
    case commit(context, box, base, ours) {
      Ok(box) -> #(box, Ok(box))
      Error(reason) -> #(box, Error(reason))
    }
  })
}

fn commit(context: Context, box: Box, base, ours) {
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
  use Nil <- result.try(case merged == box.root {
    True -> Ok(Nil)
    False ->
      case execute.files(fs.check(merged, context.state), context.state) {
        Ok(Ok(#([], _))) -> Ok(Nil)
        Ok(Ok(#(errors, _))) -> Error(Invalid(errors))
        Ok(Error(reason)) -> Error(Failed(simplifile.describe_error(reason)))
        Error(reason) -> Error(Failed(reason))
      }
  })
  case merged == box.root {
    True -> Ok(box)
    False ->
      case
        query(
          boxes.record(Box(..box, sequence: box.sequence + 1, root: merged)),
          context,
        )
      {
        Ok([box]) -> Ok(box)
        // Only the box's process records its events.
        Ok(_) -> Error(Failed("the box was changed by another process"))
        Error(reason) -> Error(reason)
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

fn query(query, context: Context) {
  case db.execute(query, context.db) {
    Ok(pog.Returned(rows:, ..)) -> Ok(rows)
    Error(reason) -> Error(Failed(string.inspect(reason)))
  }
}
