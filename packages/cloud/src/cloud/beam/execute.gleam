import eyg/interpreter/block
import eyg/interpreter/simple_debug
import eyg/parser
import gleam/option
import gleam/result

pub fn block(code: String) -> Result(String, String) {
  use source <- result.try(
    parser.all_from_string(code)
    |> result.map_error(parser.format_error(_, code)),
  )
  block.execute(source, [])
  |> result.map(fn(result) {
    result.0 |> option.map(simple_debug.inspect) |> option.unwrap("")
  })
  |> result.map_error(fn(debug) { simple_debug.describe(debug.0) })
}
