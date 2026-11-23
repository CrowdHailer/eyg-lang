//// A box is a file system that only moves to a root where all the EYG modules type check.
//// A box with a name is shared, a box without one is transient.

import cloud/apex/context.{type Context, type Open, Context, Open}
import cloud/beam/execute
import cloud/box/fs
import cloud/data/boxes.{type Box, Box}
import cloud/data/db
import cloud/data/secrets
import cloud/file_system
import cloud/registry
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, Some}
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

/// The new box starts at the current root of the original, with a copy of its secrets.
pub fn clone(
  context: Context,
  from: Box,
  name: Option(String),
) -> Result(Box, Reason) {
  use box <- result.try(start(context, name, from.root))
  use _ <- result.map(query(secrets.copy(from.id, box.id), context))
  box
}

/// The secrets of a box by name, code in the box reads them with the Env effect.
pub fn secrets(
  context: Context,
  id: String,
) -> Result(Dict(String, String), Reason) {
  query(secrets.all(id), context) |> result.map(dict.from_list)
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
      query(secrets.set(id, name, value), context) |> result.replace(Nil)
    }
  }
}

pub fn delete_secret(
  context: Context,
  id: String,
  name: String,
) -> Result(Nil, Reason) {
  query(secrets.delete(id, name), context) |> result.replace(Nil)
}

/// All the named boxes, in order of name.
pub fn named(context: Context) -> Result(List(Box), Reason) {
  query(boxes.named(), context)
}

// A name is lowercase letters, digits and dashes.
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

/// What became of a change, the box is its state after the change, or the state that refused it.
pub type Merged {
  Accepted(Box)
  Refused(Reason, Box)
}

/// Merge the changes from `base` to `ours` into the box.
pub fn merge(
  context: Context,
  id: String,
  base: v1.Cid,
  ours: v1.Cid,
) -> Result(Box, Reason) {
  case merge_with(context, id, base, ours, fn(_) { [] }) {
    Ok(Accepted(box)) -> Ok(box)
    Ok(Refused(reason, _)) -> Error(reason)
    Error(reason) -> Error(reason)
  }
}

/// Merge the changes from `base` to `ours` into the box, and record what became of them.
/// `record` gives the queries that record it, such as the output of a shell.
/// They run in the same transaction as the box's event, so either both are recorded or neither is.
/// They also run when the box refuses the change because it conflicts or does not type check.
///
/// Each box has one process that merges changes one at a time,
/// changes are made away from it and it only merges, type checks and records them.
pub fn merge_with(
  context: Context,
  id: String,
  base: v1.Cid,
  ours: v1.Cid,
  record: fn(Merged) -> List(pog.Query(Nil)),
) -> Result(Merged, Reason) {
  use box <- result.try(latest(context, id))
  registry.lookup(context.boxes, id, fn() {
    registry.serve(Open(box, check.empty()))
  })
  |> registry.call(600_000, fn(open) {
    case commit(context, open, base, ours, record) {
      Ok(#(open, merged)) -> #(open, Ok(merged))
      Error(reason) -> #(open, Error(reason))
    }
  })
}

fn commit(context: Context, open: Open, base, ours, record) {
  let Open(box, index) = open
  let checked = {
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
    case merged == box.root {
      True -> Ok(#(merged, index))
      False ->
        case
          execute.files(fs.change(index, merged, context.state), context.state)
        {
          Ok(#([], index, _)) -> Ok(#(merged, index))
          Ok(#(errors, _, _)) -> Error(Invalid(errors))
          Error(reason) -> Error(Failed(reason))
        }
    }
  }
  case checked {
    Ok(#(merged, index)) -> {
      let changed = Box(..box, sequence: box.sequence + 1, root: merged)
      let #(after, queries) = case merged == box.root {
        True -> #(box, record(Accepted(box)))
        False -> #(changed, record(Accepted(changed)))
      }
      use Nil <- result.map(
        transaction(context, fn(context) {
          use Nil <- result.try(case merged == box.root {
            True -> Ok(Nil)
            False ->
              case query(boxes.record(changed), context) {
                Ok([_]) -> Ok(Nil)
                // Only the box's process records its events.
                Ok(_) -> Error(Failed("the box was changed by another process"))
                Error(reason) -> Error(reason)
              }
          })
          list.try_each(queries, query(_, context))
        }),
      )
      #(Open(after, index), Accepted(after))
    }
    Error(Failed(_) as reason) -> Error(reason)
    Error(reason) -> {
      use Nil <- result.map(
        transaction(context, fn(context) {
          list.try_each(record(Refused(reason, box)), query(_, context))
        }),
      )
      #(open, Refused(reason, box))
    }
  }
}

fn transaction(context: Context, then) {
  db.transaction(context.db, fn(connection) {
    then(Context(..context, db: connection))
  })
  |> result.map_error(fn(error) {
    case error {
      pog.TransactionRolledBack(reason) -> reason
      pog.TransactionQueryError(reason) -> Failed(string.inspect(reason))
    }
  })
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
