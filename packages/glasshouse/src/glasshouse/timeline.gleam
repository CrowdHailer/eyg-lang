//// Reconstruct the filesystem at every point in a session.
////
//// Every filesystem effect is in a journal, with the content read or written.
//// Folding the journals in order gives the files known after each effect.
//// Files are known from the moment a program first observes or writes them,
//// files under a clone are a pointer to the commit until they are read.

import eyg/interpreter/cast
import eyg/interpreter/state
import eyg/interpreter/value as v
import glasshouse/diff
import glasshouse/journal.{type Entry}
import glasshouse/run
import glasshouse/session.{type Session}
import glasshouse/store.{type Store}
import glasshouse/value
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type Content {
  /// The whole file is known.
  Whole(bytes: BitArray)
  /// Part of the file was read from an offset.
  Part(offset: Int, bytes: BitArray)
  /// The end of a file was appended to, the rest is unknown.
  Ending(bytes: BitArray)
  /// The file exists but none of its content has been seen.
  Unseen(size: Option(Int))
}

pub type Node {
  File(content: Content)
  Directory
  /// A directory checked out from a repository.
  Checkout(url: String, commit: String)
  /// Known not to exist, it was deleted.
  Absent
}

pub type Change {
  Read(path: String, content: Content)
  Listed(path: String, children: List(String))
  Wrote(path: String, before: Option(Node), after: Content)
  Removed(path: String, before: Option(Node))
  Made(path: String)
  Cloned(path: String, url: String, commit: String)
  Committed(path: String, commit: String)
}

pub type Frame {
  Frame(
    /// Position of the effect in the whole session.
    index: Int,
    /// Position of the run's event in the session.
    event: Int,
    run: String,
    kind: run.Kind,
    /// Position of the effect in its run's journal.
    position: Int,
    entry: Entry,
    /// The files known after the effect.
    files: Dict(String, Node),
    change: Option(Change),
  )
}

/// A frame for every effect in the session, in order.
pub fn frames(session: Session, store: Store) -> List(Frame) {
  let #(_, _, frames) =
    list.index_fold(session.events, #(0, dict.new(), []), fn(acc, event, i) {
      case event {
        session.Execution(run:) ->
          list.index_fold(run.journal, acc, fn(acc, entry, position) {
            let #(index, files, frames) = acc
            let #(files, change) = apply(files, entry, store)
            let frame =
              Frame(
                index:,
                event: i,
                run: run.id,
                kind: run.kind,
                position:,
                entry:,
                files:,
                change:,
              )
            #(index + 1, files, [frame, ..frames])
          })
        _ -> acc
      }
    })
  list.reverse(frames)
}

/// The frames of a single run.
pub fn run_frames(run: run.Run, store: Store) -> List(Frame) {
  let session =
    session.Session(
      id: run.id,
      started: run.started,
      ended: run.ended,
      cwd: run.cwd,
      agent: None,
      events: [session.Execution(run)],
    )
  frames(session, store)
}

/// Apply one effect to the known files.
pub fn apply(
  files: Dict(String, Node),
  entry: Entry,
  store: Store,
) -> #(Dict(String, Node), Option(Change)) {
  let decoded = {
    use lift <- result.try(value.decode(entry.lift, store, Nil))
    use reply <- result.map(value.decode(entry.reply, store, Nil))
    #(lift, reply)
  }
  case decoded {
    Ok(#(lift, reply)) ->
      case effect_path(entry, lift) {
        Some(path) -> change(files, entry.label, path, lift, reply)
        None -> #(files, None)
      }
    Error(_) -> #(files, None)
  }
}

fn effect_path(entry: Entry, lift: state.Value(Nil)) -> Option(String) {
  case entry.path {
    Some(path) -> Some(path)
    None ->
      case lift {
        v.String(path) -> Some(path)
        v.Record(_) ->
          cast.field("path", cast.as_string, lift) |> option.from_result
        _ -> None
      }
  }
}

fn change(files, label, path, lift, reply) {
  case label, reply {
    "ReadFile", v.Tagged("Ok", v.Binary(bytes)) -> {
      let offset =
        cast.field("offset", cast.as_integer, lift) |> result.unwrap(0)
      let limit = cast.field("limit", cast.as_integer, lift) |> result.unwrap(0)
      let content = case offset == 0 && bit_array.byte_size(bytes) < limit {
        True -> Whole(bytes)
        False -> Part(offset, bytes)
      }
      let content = case dict.get(files, path), content {
        // A partial read of a file already known in full adds nothing.
        Ok(File(Whole(known))), Part(..) -> Whole(known)
        _, _ -> content
      }
      let files = directories(files, parent(path))
      #(dict.insert(files, path, File(content)), Some(Read(path, content)))
    }
    "WriteFile", v.Tagged("Ok", _) -> {
      let contents =
        cast.field("contents", cast.as_binary, lift) |> result.unwrap(<<>>)
      write(files, path, Whole(contents))
    }
    "AppendFile", v.Tagged("Ok", _) -> {
      let contents =
        cast.field("contents", cast.as_binary, lift) |> result.unwrap(<<>>)
      let content = case dict.get(files, path) {
        Ok(File(Whole(before))) -> Whole(<<before:bits, contents:bits>>)
        Ok(Absent) -> Whole(contents)
        Ok(File(Ending(before))) -> Ending(<<before:bits, contents:bits>>)
        _ -> Ending(contents)
      }
      write(files, path, content)
    }
    "DeleteFile", v.Tagged("Ok", _) -> {
      let before = dict.get(files, path) |> option.from_result
      #(dict.insert(files, path, Absent), Some(Removed(path, before)))
    }
    "MakeDirectory", v.Tagged("Ok", _) -> {
      let files = directories(files, path)
      #(files, Some(Made(path)))
    }
    "ReadDirectory", v.Tagged("Ok", v.LinkedList(children)) -> {
      let #(files, names) =
        list.fold(children, #(directories(files, path), []), fn(acc, child) {
          let #(files, names) = acc
          case listed(child) {
            Ok(#(name, node)) -> {
              let child_path = join(path, name)
              let files = case dict.get(files, child_path) {
                Ok(File(_)) | Ok(Directory) | Ok(Checkout(..)) -> files
                _ -> dict.insert(files, child_path, node)
              }
              #(files, [name, ..names])
            }
            Error(Nil) -> acc
          }
        })
      #(files, Some(Listed(path, list.reverse(names))))
    }
    "Clone", v.Tagged("Ok", reply) -> {
      let url = cast.field("url", cast.as_string, lift) |> result.unwrap("")
      let commit =
        cast.field("commit", cast.as_string, reply) |> result.unwrap("")
      let files = directories(files, parent(path))
      #(
        dict.insert(files, path, Checkout(url:, commit:)),
        Some(Cloned(path, url, commit)),
      )
    }
    "Commit", v.Tagged("Ok", reply) -> {
      let commit =
        cast.field("commit", cast.as_string, reply) |> result.unwrap("")
      let files = case dict.get(files, path) {
        Ok(Checkout(url:, ..)) ->
          dict.insert(files, path, Checkout(url:, commit:))
        _ -> files
      }
      #(files, Some(Committed(path, commit)))
    }
    _, _ -> #(files, None)
  }
}

fn write(files, path, content) {
  let before = dict.get(files, path) |> option.from_result
  let files = directories(files, parent(path))
  #(dict.insert(files, path, File(content)), Some(Wrote(path, before, content)))
}

fn listed(child) {
  use name <- result.try(
    cast.field("name", cast.as_string, child) |> result.replace_error(Nil),
  )
  case cast.field("type", Ok, child) {
    Ok(v.Tagged("Directory", _)) -> Ok(#(name, Directory))
    Ok(v.Tagged("File", details)) -> {
      let size =
        cast.field("size", cast.as_integer, details) |> option.from_result
      Ok(#(name, File(Unseen(size))))
    }
    _ -> Error(Nil)
  }
}

// Mark a directory and its parents as existing, without replacing known entries.
fn directories(files, path) {
  case path {
    "" | "/" -> files
    _ -> {
      let files = case dict.get(files, path) {
        Ok(Directory) | Ok(Checkout(..)) -> files
        _ -> dict.insert(files, path, Directory)
      }
      directories(files, parent(path))
    }
  }
}

/// The directory containing a path.
pub fn parent(path: String) -> String {
  case string.split(path, "/") |> list.reverse {
    [_] -> ""
    [_, ..rest] ->
      case list.reverse(rest) |> string.join("/") {
        "" -> "/"
        dir -> dir
      }
    [] -> ""
  }
}

fn join(directory, name) {
  case string.ends_with(directory, "/") {
    True -> directory <> name
    False -> directory <> "/" <> name
  }
}

/// The known files in path order, with clones and any directory that has no known contents.
/// Directories that only contain known files are implied by those files.
pub fn listing(files: Dict(String, Node)) -> List(#(String, Node)) {
  let present =
    dict.to_list(files)
    |> list.filter(fn(entry) { entry.1 != Absent })
  list.filter(present, fn(entry) {
    case entry.1 {
      Directory ->
        !list.any(present, fn(other) {
          string.starts_with(other.0, entry.0 <> "/")
        })
      _ -> True
    }
  })
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
}

/// A path relative to a directory, when it is inside it.
pub fn relative(path: String, directory: String) -> String {
  let prefix = case string.ends_with(directory, "/") {
    True -> directory
    False -> directory <> "/"
  }
  case string.starts_with(path, prefix) {
    True -> string.drop_start(path, string.length(prefix))
    False -> path
  }
}

/// One line describing what an effect was asked to do.
pub fn subject(entry: Entry, cwd: String, store: Store) -> String {
  let lift = value.decode(entry.lift, store, Nil)
  let text = fn(name) {
    result.try(lift, fn(lift) {
      cast.field(name, cast.as_string, lift) |> result.replace_error("")
    })
  }
  let line = case entry.path, entry.label {
    Some(path), _ -> relative(path, cwd)
    None, "NeonQuery" ->
      case text("connection"), text("query") {
        Ok(connection), Ok(query) -> connection <> " " <> query
        _, _ -> value.summary(entry.lift, store, 80)
      }
    None, "Fetch" ->
      case
        result.try(lift, fn(lift) {
          cast.field("method", Ok, lift) |> result.replace_error("")
        }),
        text("host"),
        text("path")
      {
        Ok(v.Tagged(method, _)), Ok(host), Ok(path) ->
          method <> " " <> host <> path
        _, _, _ -> value.summary(entry.lift, store, 80)
      }
    None, _ -> value.summary(entry.lift, store, 80)
  }
  let line =
    string.split(line, "\n")
    |> list.map(string.trim)
    |> string.join(" ")
  case string.length(line) > 60 {
    True -> string.slice(line, 0, 60) <> "…"
    False -> line
  }
}

/// The text of known content, if it is UTF-8.
pub fn text(content: Content) -> Option(String) {
  case content {
    Whole(bytes) | Part(bytes:, ..) | Ending(bytes) ->
      bit_array.to_string(bytes) |> option.from_result
    Unseen(_) -> None
  }
}

/// Line differences for a change to a file, when both sides are known text.
pub fn change_diff(change: Change) -> Option(List(diff.Edit)) {
  case change {
    Wrote(before:, after:, ..) -> {
      let before = case before {
        Some(File(content)) -> text(content)
        Some(Absent) | None -> Some("")
        Some(Directory) | Some(Checkout(..)) -> None
      }
      case before, after, text(after) {
        // An append to a file never read only knows the appended lines.
        _, Ending(_), Some(after) ->
          Some(list.map(diff.split(after), diff.Insert))
        Some(before), _, Some(after) -> Some(diff.lines(before, after))
        _, _, _ -> None
      }
    }
    Removed(before: Some(File(content)), ..) ->
      case text(content) {
        Some(before) -> Some(list.map(diff.split(before), diff.Delete))
        None -> None
      }
    _ -> None
  }
}

/// The path a change is about.
pub fn change_path(change: Change) -> String {
  case change {
    Read(path:, ..)
    | Listed(path:, ..)
    | Wrote(path:, ..)
    | Removed(path:, ..)
    | Made(path:)
    | Cloned(path:, ..)
    | Committed(path:, ..) -> path
  }
}

/// Did the change modify the filesystem.
pub fn is_modification(change: Change) -> Bool {
  case change {
    Read(..) | Listed(..) -> False
    Wrote(..) | Removed(..) | Made(..) | Cloned(..) | Committed(..) -> True
  }
}
