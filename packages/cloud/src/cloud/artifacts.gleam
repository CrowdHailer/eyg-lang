//// Artifacts are the files a shell creates or changes, such as a web page written by a chat's tool call.
////
//// They are stored as any other file in the box, nothing else is kept.
//// The files of a box at any root can be read by the root's content identifier, it never changes,
//// so a page links to other files beside it with relative links.
//// The changes of a shell come from its journal, each segment of a turn changed the files from the root of
//// its input to the root of its output, when the change was merged into the box.

import cloud/beam/execute
import cloud/shells/event.{type Entry}
import gleam/list
import gleam/result
import gleam/string
import multiformats/cid/v1
import unixfs/mfs

/// The paths of the files the entries changed, the most recently changed last.
pub fn changed(
  entries: List(Entry),
  state: execute.State,
) -> Result(List(String), String) {
  use changes <- result.map(
    changes(entries, [])
    |> list.try_map(fn(change) {
      execute.files(mfs.diff(change.0, change.1), state)
      |> result.map_error(string.inspect)
    }),
  )
  list.flatten(changes)
  |> list.map(fn(path) { "/" <> string.join(path, "/") })
  |> list.reverse
  |> list.unique
  |> list.reverse
}

// The root each merged segment started from and the root of its change, oldest first.
fn changes(entries, acc) {
  case entries {
    [
      event.Input(root: start, ..),
      event.Output(root:, change: event.Merged, ..),
      ..entries
    ] -> changes(entries, [#(start, root), ..acc])
    [_, ..entries] -> changes(entries, acc)
    [] -> list.reverse(acc)
  }
}

/// A file as it is in the box at `root`.
pub fn read(
  root: v1.Cid,
  path: String,
  state: execute.State,
) -> Result(BitArray, Nil) {
  let path = string.split(path, "/") |> list.filter(fn(part) { part != "" })
  execute.files(mfs.read(root, path), state)
  |> result.replace_error(Nil)
  |> result.try(result.replace_error(_, Nil))
}

/// Files a browser shows as a page or image, other files are shown as text.
pub fn content_type(path: String) -> String {
  let extension = case string.split(path, ".") |> list.reverse {
    [extension, _, ..] -> string.lowercase(extension)
    _ -> ""
  }
  case extension {
    "html" | "htm" -> "text/html; charset=utf-8"
    "svg" -> "image/svg+xml"
    "png" -> "image/png"
    "jpg" | "jpeg" -> "image/jpeg"
    "gif" -> "image/gif"
    "webp" -> "image/webp"
    "css" -> "text/css; charset=utf-8"
    "js" | "mjs" -> "text/javascript; charset=utf-8"
    "json" -> "application/json"
    _ -> "text/plain; charset=utf-8"
  }
}

/// A page or image, which is shown when a turn changes it.
pub fn viewable(path: String) -> Bool {
  case content_type(path) {
    "text/html" <> _ | "image/" <> _ -> True
    _ -> False
  }
}
