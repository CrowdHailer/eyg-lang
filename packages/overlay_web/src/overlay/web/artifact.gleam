//// Versioned documents and workspace placements. No artifact code runs here.

import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/result.{try}
import gleam/string
import touch_grass/interface

pub type File {
  File(path: String, media_type: String, content: BitArray)
}

pub type Bundle =
  List(File)

pub type Item {
  Artifact(String)
  Revision(name: String, version: Int)
  History(String)
  Diff(name: String, from: Int, to: Int)
}

pub type Point {
  Point(x: Int, y: Int)
}

pub type Placement {
  Placement(item: Item, origin: Point, size: Point)
}

pub type Effect {
  Save(name: String, bundle: Bundle)
  Show(Placement)
}

pub type Store {
  Store(versions: Dict(String, List(Bundle)), panels: List(Placement))
}

pub fn new() -> Store {
  Store(dict.new(), [])
}

pub fn effects() -> interface.Harness(Effect, a) {
  let point = t.record([#("x", t.Integer), #("y", t.Integer)])
  let revision = t.record([#("name", t.String), #("version", t.Integer)])
  let diff =
    t.record([
      #("name", t.String),
      #("from", t.Integer),
      #("to", t.Integer),
    ])
  [
    interface.Interface(
      name: "Artifact",
      lift_type: t.record([
        #("name", t.String),
        #(
          "bundle",
          t.List(
            t.record([
              #("path", t.String),
              #("media_type", t.String),
              #("content", t.Binary),
            ]),
          ),
        ),
      ]),
      lower_type: t.result(t.Integer, t.String),
      decode: decode_save,
    ),
    interface.Interface(
      name: "Show",
      lift_type: t.record([
        #(
          "item",
          t.union([
            #("Artifact", t.String),
            #("Revision", revision),
            #("History", t.String),
            #("Diff", diff),
          ]),
        ),
        #("origin", point),
        #("size", point),
      ]),
      lower_type: t.result(t.unit, t.String),
      decode: decode_show,
    ),
  ]
}

fn decode_save(raw) {
  use name <- try(cast.field("name", cast.as_string, raw))
  use bundle <- try(cast.field("bundle", cast.as_list_of(_, decode_file), raw))
  Ok(Save(name, bundle))
}

fn decode_file(raw) {
  use path <- try(cast.field("path", cast.as_string, raw))
  use media_type <- try(cast.field("media_type", cast.as_string, raw))
  use content <- try(cast.field("content", cast.as_binary, raw))
  Ok(File(path, media_type, content))
}

fn decode_point(raw) {
  use x <- try(cast.field("x", cast.as_integer, raw))
  use y <- try(cast.field("y", cast.as_integer, raw))
  Ok(Point(x, y))
}

fn decode_item(raw) {
  cast.as_varient(raw, [
    #("Artifact", cast.map(cast.as_string, Artifact)),
    #("History", cast.map(cast.as_string, History)),
    #("Revision", fn(raw) {
      use name <- try(cast.field("name", cast.as_string, raw))
      use version <- try(cast.field("version", cast.as_integer, raw))
      Ok(Revision(name, version))
    }),
    #("Diff", fn(raw) {
      use name <- try(cast.field("name", cast.as_string, raw))
      use from <- try(cast.field("from", cast.as_integer, raw))
      use to <- try(cast.field("to", cast.as_integer, raw))
      Ok(Diff(name, from, to))
    }),
  ])
}

fn decode_show(raw) {
  use item <- try(cast.field("item", decode_item, raw))
  use origin <- try(cast.field("origin", decode_point, raw))
  use size <- try(cast.field("size", decode_point, raw))
  Ok(Show(Placement(item, origin, size)))
}

pub fn history(store: Store, name: String) -> List(Bundle) {
  dict.get(store.versions, name) |> result.unwrap([])
}

pub fn revision(
  store: Store,
  name: String,
  version: Int,
) -> Result(Bundle, String) {
  let versions = history(store, name)
  case version > 0 && version <= list.length(versions) {
    True ->
      list.drop(versions, list.length(versions) - version)
      |> list.first
      |> result.replace_error("Unknown revision")
    False ->
      Error("Unknown revision: " <> name <> " #" <> int.to_string(version))
  }
}

pub fn latest(store: Store, name: String) -> Result(Bundle, String) {
  list.first(history(store, name))
  |> result.replace_error("Unknown artifact: " <> name)
}

pub fn file(bundle: Bundle, path: String) -> Result(File, Nil) {
  list.find(bundle, fn(file) { file.path == path })
}

pub fn save(
  store: Store,
  name: String,
  bundle: Bundle,
) -> Result(#(Store, Int), String) {
  use _ <- try(validate(name, bundle))
  let bytes =
    dict.values(store.versions)
    |> list.flatten
    |> list.fold(0, fn(total, bundle) { total + byte_size(bundle) })
  case bytes + byte_size(bundle) > 16_777_216 {
    True -> Error("Artifact history exceeds the 16 MiB session limit")
    False -> {
      let previous = history(store, name)
      let versions = dict.insert(store.versions, name, [bundle, ..previous])
      Ok(#(Store(..store, versions:), list.length(previous) + 1))
    }
  }
}

fn byte_size(bundle: Bundle) {
  list.fold(bundle, 0, fn(total, file) {
    total + bit_array.byte_size(file.content)
  })
}

fn validate(name, bundle) {
  case string.trim(name) == "" || string.length(name) > 120 {
    True -> Error("Artifact name must contain 1–120 characters")
    False -> {
      case list.length(bundle) > 128 || byte_size(bundle) > 2_097_152 {
        True -> Error("A bundle may contain at most 128 files and 2 MiB")
        False -> {
          use _ <- try(validate_files(bundle, dict.new()))
          case file(bundle, "index.html") {
            Ok(File(media_type: "text/html", content:, ..)) ->
              bit_array.to_string(content)
              |> result.replace(Nil)
              |> result.replace_error("index.html must be UTF-8")
            _ -> Error("Bundle requires index.html with media_type text/html")
          }
        }
      }
    }
  }
}

fn validate_files(files: Bundle, seen) {
  case files {
    [] -> Ok(Nil)
    [file, ..rest] -> {
      let segments = string.split(file.path, "/")
      let invalid =
        string.contains(file.path, "\\")
        || string.contains(file.path, ":")
        || string.contains(file.path, "?")
        || string.contains(file.path, "#")
        || string.contains(file.path, "%")
        || string.contains(file.path, "\u{0000}")
        || list.any(segments, fn(s) { s == "" || s == "." || s == ".." })
      case invalid || dict.has_key(seen, file.path) {
        True -> Error("Invalid or duplicate bundle path: " <> file.path)
        False ->
          case string.contains(file.media_type, "/") {
            False -> Error("Invalid media type: " <> file.media_type)
            True -> validate_files(rest, dict.insert(seen, file.path, Nil))
          }
      }
    }
  }
}

pub fn show(store: Store, placement: Placement) -> Result(Store, String) {
  let Placement(item, Point(x, y), Point(width, height)) = placement
  case
    x < 0
    || y < 0
    || width <= 0
    || height <= 0
    || x > 1000
    || y > 1000
    || width > 1000 - x
    || height > 1000 - y
  {
    True -> Error("Show rectangle must fit the 1000 × 1000 workspace")
    False -> {
      use _ <- try(check_item(store, item))
      let panels = case list.any(store.panels, fn(p) { p.item == item }) {
        True ->
          list.map(store.panels, fn(p) {
            case p.item == item {
              True -> placement
              False -> p
            }
          })
        False -> list.append(store.panels, [placement])
      }
      Ok(Store(..store, panels:))
    }
  }
}

fn check_item(store, item) {
  case item {
    Artifact(name) | History(name) -> latest(store, name) |> result.replace(Nil)
    Revision(name, version) ->
      revision(store, name, version) |> result.replace(Nil)
    Diff(name, from, to) -> {
      use _ <- try(revision(store, name, from))
      revision(store, name, to) |> result.replace(Nil)
    }
  }
}

pub fn close(store: Store, item: Item) -> Store {
  Store(..store, panels: list.filter(store.panels, fn(p) { p.item != item }))
}

pub fn title(item: Item) -> String {
  case item {
    Artifact(name) -> name
    History(name) -> name <> " · history"
    Revision(name, version) -> name <> " · v" <> int.to_string(version)
    Diff(name, from, to) ->
      name <> " · v" <> int.to_string(from) <> " → v" <> int.to_string(to)
  }
}

pub type Change {
  Added(File)
  Removed(File)
  Changed(before: File, after: File)
}

pub fn diff(before: Bundle, after: Bundle) -> List(Change) {
  let changes =
    list.filter_map(before, fn(old) {
      case file(after, old.path) {
        Error(_) -> Ok(Removed(old))
        Ok(new) if old != new -> Ok(Changed(old, new))
        Ok(_) -> Error(Nil)
      }
    })
  let added =
    list.filter_map(after, fn(new) {
      case file(before, new.path) {
        Error(_) -> Ok(Added(new))
        Ok(_) -> Error(Nil)
      }
    })
  list.append(changes, added)
}

pub const instructions = "
# Artifacts and workspace
Artifact({name, bundle}) saves a complete snapshot and returns Ok(version) or Error(reason).
bundle is a list of {path: String, media_type: String, content: Binary}; it must include index.html (text/html, UTF-8).
Use !string_to_binary for text; Fetch response bodies can be included directly for images.
Every successful save retains the previous versions. Names persist across your tool calls.
Show({item, origin: {x,y}, size: {x,y}}) returns Ok({}) or Error(reason).
Coordinates are integers in a 1000 by 1000 workspace, not pixels. Show upserts a panel by item.
Items: Artifact(name) follows latest; Revision({name,version}) pins a version;
History(name) shows all versions; Diff({name,from,to}) compares version numbers.
Always check effect results. Saving does NOT show a panel: call Show as well.
HTML runs in an opaque-origin sandbox with no network, storage, or access to Overlay.
Use local bundled CSS, classic scripts, images, inline SVG, and inline JavaScript.
Fetch live data in EYG first and embed it in HTML. Do not use CDN scripts, map tiles,
runtime fetch, workers or relative JS imports. A self-contained SVG map works well.
Files use relative paths; local links to scripts/styles/images are embedded by the preview.
"
