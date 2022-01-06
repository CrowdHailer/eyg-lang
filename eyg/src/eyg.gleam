import gleam/io
import gleam/list
import gleam/string
import eyg/typer/monotype as t
import eyg/typer
import eyg/codegen/javascript
import harness/harness

fn browser_to_string(_) {
  todo
}

pub fn compile(expected, untyped) {
  let scope =
    typer.root_scope([
      #("equal", typer.equal_fn()),
      #("harness", harness.string()),
    ])
  let state = #(typer.init(browser_to_string), scope)
  let #(typed, typer) = typer.infer(untyped, expected, state)
  let #(typed, typer) = typer.expand_providers(typed, typer)
  case typer.inconsistencies {
    [] -> fn(handle) {
      let #(ok, _) = handle
      ok(javascript.eval(typed, typer, browser_to_string))
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
