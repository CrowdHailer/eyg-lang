import gleam/io
import eyg/ast
import eyg/ast/pattern as p
import eyg/typer

pub fn boolean_case_test() {
  let untyped =
    ast.case_(
      ast.variable("x"),
      [
        #("True", p.Tuple([]), ast.binary("foo")),
        #("True", p.Tuple([]), ast.tuple_([])),
      ],
    )
  let #(typed, typer) = typer.infer_unconstrained(untyped)
  io.debug(typed)
  io.debug(typer.inconsistencies)
  todo("boolean")
}
