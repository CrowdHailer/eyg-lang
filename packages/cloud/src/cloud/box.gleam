//// A box is a named file system that only moves to a root where all the EYG modules type check.

import cloud/apex/context.{type Context}
import cloud/beam/execute
import cloud/box/fs
import cloud/box/memory
import cloud/data/boxes.{type Box, Box}
import cloud/file_system
import gleam/result
import multiformats/cid/v1
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
  memory.get(context.memory, name) |> result.replace_error(Missing)
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

fn start(context: Context, box) {
  case memory.add(context.memory, box) {
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

fn record(context: Context, box) {
  case memory.record(context.memory, box) {
    True -> Ok(box)
    False -> Error(Conflict)
  }
}

fn failed(reason) {
  Failed(simplifile.describe_error(reason))
}
