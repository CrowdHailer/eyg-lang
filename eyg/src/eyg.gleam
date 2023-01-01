import gleam/dynamic.{Dynamic}
import gleam/io
import gleam/list
import gleam/string
import eyg/typer/monotype as t
import eyg/typer
import eyg/typer/harness
import eyg/codegen/javascript
import platform/browser
import entry
import gleam/javascript/array.{Array}

pub fn compile_unconstrained(expression, harness) {
  let harness.Harness(variables) = harness
  let typer__ = typer.init()
  let scope = typer.root_scope(variables)
  let #(x, typer) = typer.next_unbound(typer__)
  let expected = t.Unbound(x)
  let #(typed, typer) =
    typer.infer(expression, expected, t.empty, #(typer, scope))
  typer.expand_providers(typed, typer, [])
}

// document that rad start shell at dollar
// This becomes the entry point
external fn args(Int) -> Array(String) =
  "" "process.argv.slice"

// zero arity
pub fn main() {
  entry.main(array.to_list(args(1)))
}
