import gleam/io
import gleam/list
import eyg/ast
import eyg/ast/pattern
import eyg/codegen/javascript
import eyg/typer.{infer, init}
import eyg/typer/monotype.{resolve}
import eyg/typer/polytype.{State}

// TODO need to handle generalisation step in functions, I think might be all right BUT monomorphization would help.
// usecases 
// read file to string at compile time maybe a SQL query https://github.com/gleam-lang/suggestions/issues/125
// Type checked template library https://github.com/gleam-lang/suggestions/issues/118
// projection and joins for records/spreadsheets
// type safe SQL https://github.com/gleam-lang/suggestions/issues/31
// At the moment the provider is written in Gleam and is programatically part of the compiler
// This is not a problem, works with the language as a library approach.
// End users might be writing there own helper functions for filter/map or rows/dataframes but they are unlikely to be writing there own providers.
fn env_provider(_config, hole) {
  case hole {
    monotype.Row(fields, _) ->
      ast.Row(list.map(
        fields,
        fn(field) {
          case field {
            #(name, monotype.Binary) -> #(name, ast.Binary(name))
            #(name, _) -> #(name, ast.Binary(name))
          }
        },
      ))
  }
}

// TODO js return type is not correct in let
// The id in the provider should be generated. I'm using 999 as it's bigger than any unbound variable.
pub fn config_test() {
  let typer =
    init(
      []
      |> with_equal(),
    )
  let untyped =
    ast.Let(
      pattern.Row([#("foo", "foo"), #("bar", "bar")]),
      ast.Provider(999, env_provider("", _)),
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
// Render with units/currencies Can access the phantom type
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
