import gleam/io
import gleam/list
import gleam/string
import eyg/typer/monotype as t
import eyg/typer
import eyg/typer/harness

// TODO remove
pub fn compile_unconstrained(expression, harness) {
  let harness.Harness(variables, _) = harness
  let typer__ = typer.init()
  let scope = typer.root_scope(variables)
  let #(x, typer) = typer.next_unbound(typer__)
  let expected = t.Unbound(x)
  let #(typed, typer) = typer.infer(expression, expected, #(typer, scope))
  typer.expand_providers(typed, typer)
}
