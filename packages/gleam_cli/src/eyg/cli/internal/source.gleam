import eyg/ir/dag_json
import eyg/ir/tree as ir
import eyg/parser
import eyg/parser/parser.{describe_reason} as _
import gleam/json
import gleam/result.{try}
import simplifile

pub fn read(file: String) -> Result(#(ir.Expression(Nil), Nil), String) {
  use code <- try(
    simplifile.read(file) |> result.map_error(simplifile.describe_error),
  )

  case json.parse(code, dag_json.decoder(Nil)) {
    Ok(source) -> Ok(source)
    Error(_) ->
      case parser.all_from_string(code) {
        Ok(source) -> Ok(ir.clear_annotation(source))
        Error(reason) -> Error(describe_reason(reason))
      }
  }
}
