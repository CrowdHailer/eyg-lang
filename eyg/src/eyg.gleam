import gleam/io
import gleam/list
import gleam/string
import eyg/typer/monotype as t
import eyg/typer
import eyg/codegen/javascript
import harness/harness

pub fn compile(expected, untyped) {
  let scope =
    typer.root_scope([
      #("equal", typer.equal_fn()),
      #("harness", harness.string()),
    ])
  let state = #(typer.init(fn(_) { "TODO" }), scope)
  let #(typed, typer) = typer.infer(untyped, expected, state)
  let #(typed, typer) = typer.expand_providers(typed, typer)
  case typer.inconsistencies {
    [] -> fn(handle) {
      let #(ok, _) = handle
      ok(javascript.eval(typed, typer))
    }
    inconsistencies -> fn(handle) {
      let #(_, err) = handle
      err(string.join(list.map(
        inconsistencies,
        fn(x: #(List(Int), String)) { x.1 },
      )))
    }
  }
}
