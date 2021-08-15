import eyg/ast
import eyg/typer.{infer, init}
import eyg/typer/monotype

pub fn infer_type_of_tuple_test() {
  let typer = init()
  let untyped = ast.Tuple([])
  let Ok(#(type_, _typer)) = infer(untyped, typer)
  assert monotype.Tuple([]) = type_
}

pub fn infer_type_of_nested_tuple_test() {
  let typer = init()
  let untyped = ast.Tuple([ast.Tuple([])])
  let Ok(#(type_, _typer)) = infer(untyped, typer)
  assert monotype.Tuple([monotype.Tuple([])]) = type_
}
