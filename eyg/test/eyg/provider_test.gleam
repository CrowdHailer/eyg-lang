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


// TODO js return type is not correct in let
// The id in the provider should be generated. I'm using 999 as it's bigger than any unbound variable.
pub fn config_test() {
  let typer =
    init(
      []
      |> with_equal(),
    )
  let untyped =
    ast.let_(
      pattern.Row([#("foo", "foo"), #("bar", "bar")]),
      ast.provider(env_provider("", _)),
      ast.call(
        ast.variable("equal"),
        ast.tuple_([ast.variable("foo"), ast.binary("secret")]),
      ),
    )
  let #(typed, typer) = infer(untyped, monotype.Unbound(-1), typer)
  javascript.render(typed, #(False, [], typer))
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
