import gleam/io
import eyg/ast
import eyg/ast/pattern
import eyg/codegen/javascript
import eyg/typer.{infer, init}
import eyg/typer/monotype.{resolve}
import eyg/typer/polytype.{State}

// At the moment the provider is written in Gleam and is programatically part of the compiler
fn env_provider(_config, hole) {
  todo
}

pub fn config_test() {
  let typer =
    init(
      []
      |> with_equal(),
    )
  let untyped =
    ast.Let(
      pattern.Row([#("foo", "foo"), #("bar", "bar")]),
      ast.Provider(999),
      ast.Call(
        ast.Variable("equal"),
        ast.Tuple([ast.Variable("foo"), ast.Binary("secret")]),
      ),
    )
  let Ok(#(_, typer)) = infer(untyped, typer)
  javascript.render(untyped, #(False, [], typer))
  |> io.debug
}

// Format
// Templates
// Hole TODO Unimplemented
// Object.entries(process.env) returns array of tuples
fn with_equal(previous) {
  [
    #(
      "equal",
      polytype.Polytype(
        [1],
        monotype.Function(
          monotype.Tuple([monotype.Unbound(1), monotype.Unbound(1)]),
          monotype.Nominal("Boolean", []),
        ),
      ),
    ),
    ..previous
  ]
}
