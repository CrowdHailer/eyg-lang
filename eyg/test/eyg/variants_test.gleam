import gleam/io
import eyg/ast
import eyg/ast/pattern
import eyg/typer.{infer, init, resolve}
import eyg/typer/monotype
import eyg/typer/polytype

pub fn infer_variant_test() {
  let typer = init([])
  let untyped = ast.Call(ast.Constructor("Boolean", "True"), ast.Tuple([]))
  let Ok(#(type_, typer)) = infer(untyped, typer)
  io.debug(type_)
  io.debug(resolve(type_, typer))
  io.debug(typer)
  assert monotype.Nominal("Boolean", []) = resolve(type_, typer)
}

pub fn infer_concrete_parameterised_variant_test() {
  let typer = init([])
  //   Think we might always put in tuple in my language
  let untyped = ast.Call(ast.Constructor("Option", "Some"), ast.Binary("value"))
  let Ok(#(type_, typer)) = infer(untyped, typer)
  assert monotype.Nominal("Option", [monotype.Binary]) = resolve(type_, typer)
}

pub fn infer_unspecified_parameterised_variant_test() {
  let typer = init([])
  let untyped = ast.Call(ast.Constructor("Option", "None"), ast.Tuple([]))
  let Ok(#(type_, typer)) = infer(untyped, typer)
  assert monotype.Nominal("Option", [monotype.Unbound(_)]) =
    resolve(type_, typer)
}


// TODO unknown named type
// TODO unknown variant
// TODO creating duplicate name
// TODO pattern destructure OR case