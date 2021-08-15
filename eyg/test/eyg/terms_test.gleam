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

pub fn infer_binary_test() {
  let typer = init()
  let untyped = ast.Binary("Hello")
  let Ok(#(type_, _typer)) = infer(untyped, typer)
  assert monotype.Binary = type_
}

pub fn infer_row_test() {
  let typer = init()
  let untyped = ast.Row([#("foo", ast.Tuple([]))])
  let Ok(#(type_, _typer)) = infer(untyped, typer)
  assert monotype.Row([#("foo", monotype.Tuple([]))]) = type_
}
