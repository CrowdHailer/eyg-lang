//// A box is a named file system that only moves to a root where all the EYG modules type check.
////
//// A box is kept in memory, see `box/memory`, until a session is made in it.
//// Then it is made durable, its events are recorded in Postgres and every later event is recorded there.

import cloud/apex/context.{type Context}
import cloud/beam/execute
import cloud/box/fs
import cloud/box/memory
import cloud/data/boxes.{type Box, Box}
import cloud/file_system
import gleam/list
import gleam/result
import gleam/string
import multiformats/cid/v1
import pog
import simplifile
import unixfs/mfs

pub type Reason {
  Missing
  /// The box name is taken or the box changed while this change was being made.
  Conflict
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
  case memory.take(context.memory, name) {
    Error(Nil) -> Ok(Nil)
    Ok(events) -> save(context, events)
  }
}

fn save(context: Context, events: memory.Events) {
  list.try_each(events, fn(box) { query(boxes.record(box), context) })
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
    False -> Error(Conflict)
  }
}

/// Make a change to the files in a box, the effect returns the new root.
pub fn change(
  context: Context,
  box: Box,
  effect: mfs.Effect(Result(v1.Cid, simplifile.FileError)),
) -> Result(Box, Reason) {
  case execute.files(effect, context.state) {
    Ok(Ok(root)) -> commit(context, box, root)
    Ok(Error(reason)) -> Error(Invalid([simplifile.describe_error(reason)]))
    Error(reason) -> Error(Failed(reason))
  }
}

/// Move the box to a new root if the file system there is valid.
pub fn commit(context: Context, box: Box, root: v1.Cid) -> Result(Box, Reason) {
  case root == box.root {
    True -> Ok(box)
    False ->
      case execute.files(fs.check(root, context.state), context.state) {
        Ok(Ok(#([], _))) ->
          record(context, Box(box.name, box.sequence + 1, root))
        Ok(Ok(#(errors, _))) -> Error(Invalid(errors))
        Ok(Error(reason)) -> Error(failed(reason))
        Error(reason) -> Error(Failed(reason))
      }
  }
}

// A box in memory keeps its events there, a durable box records them in Postgres.
fn record(context: Context, box: Box) {
  case memory.get(context.memory, box.name) {
    Ok(_) ->
      case memory.record(context.memory, box) {
        True -> Ok(box)
        False -> Error(Conflict)
      }
    Error(Nil) ->
      case query(boxes.record(box), context) {
        Ok([box]) -> Ok(box)
        Ok(_) -> Error(Conflict)
        Error(reason) -> Error(reason)
      }
  }
}

fn failed(reason) {
  Failed(simplifile.describe_error(reason))
}

fn query(query, context: Context) {
  case pog.execute(query, context.db) {
    Ok(pog.Returned(rows:, ..)) -> Ok(rows)
    Error(reason) -> Error(Failed(string.inspect(reason)))
  }
}
