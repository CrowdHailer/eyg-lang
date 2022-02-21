import gleam/io
import gleam/option.{None, Some}
import gleam/list
import gleam/string
import eyg/ast
import eyg/ast/encode
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/codegen/javascript
import eyg/typer
import eyg/typer/monotype as t
import eyg/typer/polytype
import platform/browser

pub fn simple_reload_test() {
  // take in a new program and call values
  let untyped =
    ast.function(
      p.Variable("source"),
      ast.let_(
        p.Variable("value"),
        // call the provider loader
        ast.call(ast.provider("", e.Loader), ast.variable("source")),
        ast.call(
          ast.variable("equal"),
          ast.tuple_([ast.binary("FOO"), ast.variable("value")]),
        ),
      ),
    )
  let state = #(
    typer.init(browser.native_to_string),
    typer.root_scope([#("equal", typer.equal_fn())]),
  )

  let #(typed, typer) = typer.infer(untyped, t.Unbound(-1), state)
  let #(typed, typer) = typer.expand_providers(typed, typer)

  assert [] = typer.inconsistencies
  javascript.render(
    typed,
    javascript.Generator(False, [], typer, None, browser.native_to_string),
  )
  |> list.intersperse("\n")
  |> string.concat()
  |> io.debug
  //   todo
}
