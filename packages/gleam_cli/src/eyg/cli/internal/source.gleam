import eyg/ir/dag_json
import eyg/ir/tree as ir
import eyg/parser
import eyg/parser/location
import gleam/json
import gleam/list
import gleam/option
import gleam/result.{try}
import simplifile

pub type Input {
  File(path: String)
  Code(code: String)
  Stdin
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

pub fn parse(code: String) -> Result(ir.Node(location.Span), String) {
  case json.parse(code, dag_json.decoder(#(0, 0))) {
    Ok(source) -> Ok(source)
    Error(_) ->
      case parser.all_from_string(code) {
        Ok(source) -> Ok(source)
        Error(reason) -> Error(parser.format_error(reason, code))
      }
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
