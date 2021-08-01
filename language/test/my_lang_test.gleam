import language/ast
import language/type_.{Data, Function}
import my_lang/list

pub fn list_test() {
  let Ok(#(type_, tree, substitutions)) =
    ast.infer(list.reverse(), list.types())
  let Function([Data("List", [a])], Data("List", [r])) =
    type_.resolve_type(type_, substitutions)
  let True = a == r

  let Ok(#(type_, tree, substitutions)) = ast.infer(list.module(), list.types())
//   let Function([Data("List", [a])], Data("List", [r])) =
//     type_.resolve_type(type_, substitutions)
//   let True = a == r
  Ok(Nil)
}
