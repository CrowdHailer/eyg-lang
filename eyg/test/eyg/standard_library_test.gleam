import gleam/list
import gleam/io
import eyg/ast
import eyg/ast/pattern
import standard/boolean
import eyg/typer.{init}
import standard/library.{compile}
import eyg/typer/monotype
import eyg/typer/polytype

external fn run(String) -> a =
  "../harness.js" "run"

// Can start on the row macros for joining
pub fn standard_library_test() {
  let untyped =
    ast.Let(pattern.Variable("boolean"), boolean.code(), boolean.test())
  compile(
    untyped,
    init([
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
      #(
        "hole",
        polytype.Polytype(
          [1],
          monotype.Function(
            monotype.Tuple([monotype.Binary]),
            monotype.Unbound(1),
          ),
        ),
      ),
      #(
        "debug",
        polytype.Polytype(
          [1],
          monotype.Function(monotype.Unbound(1), monotype.Unbound(1)),
        ),
      ),
    ]),
  )
  |> io.debug()
  |> run
}
