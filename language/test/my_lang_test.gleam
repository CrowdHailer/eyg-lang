import language/ast
import language/type_.{Data, Function}
import language/scope
import my_lang/list
// pub fn list_test() {
//   let Ok(#(type_, tree, substitutions)) = ast.infer(list.reverse(), scope.new())
//   let Function([Data("List", [a])], Data("List", [r])) =
//     type_.resolve_type(type_, substitutions)
//   let True = a == r
//   let Ok(#(type_, tree, substitutions)) = ast.infer(list.module(), scope.new())
//   //   let Function([Data("List", [a])], Data("List", [r])) =
//   //     type_.resolve_type(type_, substitutions)
//   //   let True = a == r
//   Ok(Nil)
// }
