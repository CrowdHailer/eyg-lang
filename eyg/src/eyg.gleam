import gleam/dynamic.{Dynamic}
import gleam/io
import gleam/list
import gleam/string
import eyg/ast/encode
import eyg/typer/monotype as t
import eyg/typer
import eyg/typer/harness
import eyg/codegen/javascript
import eyg/editor/type_info
import platform/browser

pub fn compile_unconstrained(expression, harness) {
  let harness.Harness(variables, _, native_to_parameters) = harness
  let typer__ = typer.init(native_to_parameters)
  let scope = typer.root_scope(variables)
  let #(x, typer) = typer.next_unbound(typer__)
  let expected = t.Unbound(x)
  let #(typed, typer) = typer.infer(expression, expected, #(typer, scope))
  typer.expand_providers(typed, typer, [])
}

pub fn provider(source, constraint) -> Result(Dynamic, String) {
  let harness.Harness(variables, native_to_string, native_to_parameters) = browser.harness()
  let untyped = encode.from_json(encode.json_from_string(source))
  let scope = typer.root_scope(variables)
  let typer = typer.init(native_to_parameters)
  let #(typed, typer) = typer.infer(untyped, constraint, #(typer, scope))
  let #(typed, typer) = typer.expand_providers(typed, typer, variables)

  case typer.inconsistencies {
    [] -> Ok(javascript.eval(typed, typer))
    _ ->
      Error(string.join(
        list.map(
          typer.inconsistencies,
          fn(i) {
            let #(_path, reason) = i
            type_info.reason_to_string(reason, native_to_string)
          },
        ),
        " & ",
      ))
  }
}
