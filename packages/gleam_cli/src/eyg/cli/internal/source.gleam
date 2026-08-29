import eyg/cli/system
import eyg/ir/dag_json
import eyg/ir/tree as ir
import eyg/parser
import eyg/parser/location
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import multiformats/cid/v1

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
  Location(origin: Origin, source: Source)
}

/// A span carrying its source-of-truth.
pub type Source {
  Text(code: String, span: location.Span)
  Json
}

/// Read the source a command was given, from a file, standard input, or the
/// command line.
pub fn read_input(input: Input) -> system.Effect(Result(String, String)) {
  case input {
    File(path:) -> {
      use code <- system.then(system.read_file(path))
      system.Done(result.map(code, strip_shebang))
    }
    Code(code:) -> system.Done(Ok(code))
    Stdin -> system.stdin()
  }
}

/// Drop the `#!` line a script file starts with.
///
/// The line makes a module runnable as a command and is not part of the
/// source, so every reader of a file drops it.
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
    File(path:) -> Disk(path:)
    Code(code: _) -> Inline
    Stdin -> Pipe
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

pub fn span(location: Location) {
  let Location(_origin, source) = location
  case source {
    Text(code: _, span:) -> span
    Json -> #(0, 0)
  }
}
