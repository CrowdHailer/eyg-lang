//// Common utilities for sourcing code from a file system.

import eyg/ir/dag_json
import eyg/ir/tree as ir
import eyg/parser
import eyg/parser/location
import filepath
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import multiformats/cid/v1
import touch_grass/file_system

/// Input defines how can be supplied when starting the program.
pub type Input {
  File(path: String)
  Code(code: String)
  Stdin
}

/// Where source code originated from.
/// 
/// - `Inline` code was provided as input, either on stdin or as a code argument.
/// - `Content` and `Release` where pulled from the hub on demand.
/// - `Host` from input provided as a path or a relative reference.
pub type Origin {
  Inline
  Content(cid: v1.Cid)
  Release(package: String, version: Int, cid: v1.Cid)
  Host(path: String)
}

pub type Location {
  Location(origin: Origin, source: Source)
}

/// A span carrying its source-of-truth.
pub type Source {
  Text(code: String, span: location.Span)
  Json
}

pub fn strip_shebang(code: String) -> String {
  case string.starts_with(code, "#!") {
    True ->
      case string.split_once(code, "\n") {
        Ok(#(_, rest)) -> rest
        Error(Nil) -> ""
      }
    False -> code
  }
}

/// parse the code adding it's span to an origin identifier
pub fn parse(
  code: String,
  origin: Origin,
) -> Result(ir.Node(Location), String) {
  let code = strip_shebang(code)
  case json.parse(code, dag_json.decoder(Location(origin, Json))) {
    Ok(source) -> Ok(source)
    Error(_) ->
      case parser.all_from_string(code) {
        Ok(source) -> {
          let source =
            ir.map_annotation(source, fn(span) {
              Location(origin, Text(code, span))
            })
          Ok(source)
        }
        Error(reason) -> Error(parser.format_error(reason, code))
      }
  }
}

pub fn parse_input(code: String, input: Input) {
  let origin = input_origin(input)
  parse(code, origin)
}

/// Input is valid input this doesn't include release or module, the origin type does.
pub fn input_origin(input) {
  case input {
    File(path:) -> Host(path:)
    Code(code: _) | Stdin -> Inline
  }
}

/// Normalize a file input against an explicit working directory.
pub fn normalize_input(working_directory: String, input: Input) {
  case input {
    File(path:) -> {
      use path <- result.map(
        file_system.resolve_path(Some(working_directory), path)
        |> result.replace_error("invalid relative path outside filesystem"),
      )
      File(path)
    }
    Code(_) | Stdin -> Ok(input)
  }
}

/// The directory for relative paths from this origin.
/// Published modules have no filesystem base.
pub fn base(origin: Origin, cwd: String) -> Option(String) {
  case origin {
    Host(path) -> Some(filepath.directory_name(path))
    Inline -> Some(cwd)
    Content(_) | Release(..) -> None
  }
}

pub fn block_expression(code) {
  use #(#(assignments, tail), _) <- result.map(parser.block_from_string(code))
  let tail = option.unwrap(tail, #(ir.Vacant, #(0, 0)))

  list.fold_right(assignments, tail, fn(acc, assignment) {
    let #(label, value, at) = assignment
    #(ir.Let(label, value, acc), at)
  })
}

pub fn code(location: Location) {
  let Location(_origin, source) = location
  case source {
    Text(code:, span: _) -> code
    Json -> ""
  }
}

pub fn origin_label(origin: Origin, cwd: String) -> String {
  case origin {
    Host(path:) -> string.replace(path, cwd <> "/", "")
    Inline -> "<inline>"
    Content(cid:) -> "#" <> v1.to_string(cid)
    Release(package:, version:, cid: _) ->
      "@" <> package <> ":" <> int.to_string(version)
  }
}

pub fn span(location: Location) {
  let Location(_origin, source) = location
  case source {
    Text(code: _, span:) -> span
    Json -> #(0, 0)
  }
}

/// 1-based line number for a byte offset into `code`. Returns 0 when
/// `code` is empty.
pub fn line_at(code: String, offset: Int) -> Int {
  case code {
    "" -> 0
    _ -> string.slice(code, 0, offset) |> string.split("\n") |> list.length
  }
}
