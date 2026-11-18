//// Artifacts are the files a session creates or changes, such as a web page an llm writes.
////
//// They are stored as any other file in the box, nothing else is kept.
//// The files of a box at any root can be read by the root's content identifier, it never changes,
//// so a page links to other files beside it with relative links.
//// The changes of a session come from its events, each segment of a turn changed the files from the root it
//// resumed from to the root that ended it, unless the box rejected the change.

import cloud/beam/execute
import cloud/sessions/event.{type Event}
import gleam/list
import gleam/result
import gleam/string
import multiformats/cid/v1
import unixfs/mfs

/// The paths of the files the events changed, the most recently changed last.
pub fn changed(
  events: List(Event),
  state: execute.State,
) -> Result(List(String), String) {
  use changes <- result.map(
    changes(events, [])
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

// The root each segment resumed from and the root of its change, oldest first.
fn changes(events, acc) {
  case events {
    [event.Resumed(start), ..events] -> segment(start, events, acc)
    [_, ..events] -> changes(events, acc)
    [] -> list.reverse(acc)
  }
}

fn segment(start, events, acc) {
  case events {
    [ended, ..rest] ->
      case ended, rest {
        // A change the box rejected was discarded.
        event.Requested(..), [event.Answered(execute.Rejected(_)), ..]
        | event.Slept(..), [event.Answered(execute.Rejected(_)), ..]
        | event.Asked(..), [event.Answered(execute.Rejected(_)), ..]
        | event.Returned(..), [event.Finished(Error(_), ..), ..]
        -> changes(rest, acc)
        event.Requested(root:, ..), _
        | event.Slept(root:, ..), _
        | event.Asked(root:, ..), _
        | event.Returned(root:, ..), _
        -> changes(rest, [#(start, root), ..acc])
        _, _ -> segment(start, rest, acc)
      }
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
