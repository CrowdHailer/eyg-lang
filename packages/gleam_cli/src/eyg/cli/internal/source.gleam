import eyg/ir/dag_json
import eyg/ir/tree as ir
import eyg/parser
import gleam/json
import gleam/list
import gleam/option
import gleam/result.{try}
import simplifile

pub fn read(file: String) -> Result(ir.Node(Nil), String) {
  use code <- try(
    simplifile.read(file) |> result.map_error(simplifile.describe_error),
  )

  case json.parse(code, dag_json.decoder(Nil)) {
    Ok(source) -> Ok(source)
    Error(_) ->
      case parser.all_from_string(code) {
        Ok(source) -> Ok(ir.clear_annotation(source))
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
