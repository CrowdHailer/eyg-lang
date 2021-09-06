import gleam/string
import gleam/list
import gleam/io
import eyg/ast
import eyg/ast/pattern
import eyg/typer/monotype
import eyg/typer.{infer, init}
import eyg/codegen/javascript
import eyg/codegen/utilities
import standard/boolean

pub fn compile(untyped, scope) {
  case infer(untyped, monotype.Unbound(-1), scope) {
    #(typed, typer) ->
      javascript.maybe_wrap_expression(typed, #(False, [], typer))
      |> list.intersperse("\n")
      |> string.join()
  }
  // TODO handle failure case
  // Error(reason) -> {
  //   io.debug(reason)
  //   todo("failed to compile")
  // }
}
