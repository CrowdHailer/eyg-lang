import eyg/ir/dag_json
import eyg/ir/tree as ir
import eyg/parser
import eyg/parser/location
import gleam/json
import gleam/list
import gleam/option
import gleam/result.{try}
import multiformats/cid/v1
import simplifile

pub type Input {
  File(path: String)
  Code(code: String)
  Stdin
}

/// Where a piece of IR ultimately came from.
pub type Origin {
  Disk(path: String)
  Pipe
  Inline
  Repl
  Content(cid: v1.Cid)
  Release(package: String, version: Int, cid: v1.Cid)
}

pub type Location {
  Location(Origin, Source)
}

/// A span carrying its source-of-truth.
pub type Source {
  Text(code: String, span: location.Span)
  Json
}

pub fn read_input(input: Input) -> Result(String, String) {
  case input {
    File(path:) -> read_file(path)
    Code(code:) -> Ok(code)
    Stdin -> read_stdin()
  }
}

@external(javascript, "./source_ffi.mjs", "readStdin")
fn read_stdin() -> Result(String, String)

pub fn read_file(file: String) -> Result(String, String) {
  use code <- try(
    simplifile.read(file) |> result.map_error(simplifile.describe_error),
  )

  Ok(code)
}

/// parse the code adding it's span to an origin identifier
pub fn parse(code: String, origin: Origin) -> Result(ir.Node(Location), String) {
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
  let origin = case input {
    File(path:) -> Disk(path:)
    Code(code: _) -> Inline
    Stdin -> Pipe
  }
  parse(code, origin)
}

pub fn block_expression(code) {
  use #(#(assignments, tail), _) <- result.map(parser.block_from_string(code))
  let tail = option.unwrap(tail, #(ir.Vacant, #(0, 0)))

  list.fold_right(assignments, tail, fn(acc, assignment) {
    let #(label, value, at) = assignment
    #(ir.Let(label, value, acc), at)
  })
}

pub fn span(location: Location) {
  let Location(_origin, source) = location
  case source {
    Text(code: _, span:) -> span
    Json -> #(0, 0)
  }
}
