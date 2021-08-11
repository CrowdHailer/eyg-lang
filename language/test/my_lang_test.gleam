import gleam/io
import gleam/option.{None}
import gleam/list as gleam_list
import gleam/string
import language/ast
import language/codegen/javascript
import language/type_.{Data, Function, Row, Variable}
import language/scope
import my_lang/list

pub fn list_test() {
  let Ok(#(type_, tree, substitutions)) = ast.infer(list.module(), scope.new())
  let Row(exports, None) = type_.resolve_type(type_, substitutions)
  let Ok(Function(
    [Variable(a), Data("list::List", [Variable(b)])],
    Data("list::List", [Variable(c)]),
  )) = gleam_list.key_find(exports, "Cons")
  let True = a == b
  let True = b == c
  // TODO tests
  javascript.maybe_wrap_expression(#(type_, tree))
  |> gleam_list.intersperse("\n")
  |> string.concat()
  // |> io.debug()
  // |> io.print()
  // let 1 = 2
  // Ok(Nil)
}
// function main(x) {
//   return x + main(1);
// }
// look at generated Gleam
// TODO JS recursion, Do we want a key word for tail call optimisation only.
