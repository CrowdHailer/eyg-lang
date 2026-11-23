//// A box is a file system that only moves to a root where all the EYG modules type check.
//// A box with a name is shared, a box without one is transient.

import cloud/apex/context.{type Context}
import cloud/beam/execute
import cloud/box/fs
import cloud/data/boxes.{type Box, Box}
import cloud/data/db
import cloud/file_system
import gleam/option.{type Option}
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
  /// The box changed while this change was being made.
  Conflict
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
    Ok(Ok(root)) -> commit(context, box, root)
    Ok(Error(reason)) -> Error(Invalid([simplifile.describe_error(reason)]))
    Error(reason) -> Error(Failed(reason))
  }
}

// Move the box to a new root if the file system there is valid.
// The change is recorded as the next event, if another change was recorded first it conflicts.
fn commit(context: Context, box: Box, root) {
  case root == box.root {
    True -> Ok(box)
    False ->
      case execute.files(fs.check(root, context.state), context.state) {
        Ok(Ok(#([], _))) ->
          case
            query(
              boxes.record(Box(..box, sequence: box.sequence + 1, root:)),
              context,
            )
          {
            Ok([box]) -> Ok(box)
            Ok(_) -> Error(Conflict)
            Error(reason) -> Error(reason)
          }
        Ok(Ok(#(errors, _))) -> Error(Invalid(errors))
        Ok(Error(reason)) -> Error(Failed(simplifile.describe_error(reason)))
        Error(reason) -> Error(Failed(reason))
      }
  }
}

fn query(query, context: Context) {
  case db.execute(query, context.db) {
    Ok(pog.Returned(rows:, ..)) -> Ok(rows)
    Error(reason) -> Error(Failed(string.inspect(reason)))
  }
}
