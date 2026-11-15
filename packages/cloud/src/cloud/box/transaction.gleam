//// Candidate construction is pure. Only the owner publishes a checked root.

import cloud/beam/file_system
import gleam/list
import gleam/result
import multiformats/cid/v1

pub type Change {
  Put(path: String, contents: BitArray)
  MakeDirectory(path: String)
  Delete(path: String)
}

pub type Error {
  Conflict(current: v1.Cid)
  Denied(path: String)
  Invalid(reason: String)
}

pub fn path(change: Change) {
  case change {
    Put(path, _) | MakeDirectory(path) | Delete(path) -> path
  }
}

pub fn canonical(change: Change) {
  use path <- result.map(file_system.resolve_path(path(change)))
  case change {
    Put(_, contents) -> Put(path, contents)
    MakeDirectory(_) -> MakeDirectory(path)
    Delete(_) -> Delete(path)
  }
}

pub fn prepare(
  current: file_system.State,
  base: v1.Cid,
  changes: List(Change),
  authorize: fn(Change) -> Bool,
) -> Result(file_system.State, Error) {
  case current.root == base {
    False -> Error(Conflict(current.root))
    True -> {
      use changes <- result.try(
        list.try_map(changes, canonical) |> result.map_error(Invalid),
      )
      // Check the whole batch before constructing it. Authorization captures the
      // committed policy, never any policy installed by the candidate.
      use _ <- result.try(
        list.try_each(changes, fn(change) {
          case authorize(change) {
            True -> Ok(Nil)
            False -> Error(Denied(path(change)))
          }
        }),
      )
      list.try_fold(changes, current, fn(files, change) {
        let #(outcome, files) = case change {
          Put(path, contents) -> file_system.write(files, path, contents)
          MakeDirectory(path) -> file_system.make_directory(files, path)
          Delete(path) -> file_system.delete(files, path)
        }
        result.replace(outcome, files) |> result.map_error(Invalid)
      })
    }
  }
}
