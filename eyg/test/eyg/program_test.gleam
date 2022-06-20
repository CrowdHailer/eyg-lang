// import gleam/io
// import eyg
// import eyg/ast/expression as e
// import eyg/ast/pattern as p
// import eyg/ast/encode
// import eyg/typer
// import eyg/typer/monotype as t
// import platform/browser
// // does a pure/empty platform exist Ivory tower but that won;t even have equal
// // NOTE this relies on label being defined only once
// fn fetch(tree, label) {
//   let #(_, expression) = tree
//   case expression {
//     e.Let(p.Variable(l), value, _) if l == label -> Ok(value)
//     e.Let(_, _, then) -> fetch(then, label)
//     _ -> Error(Nil)
//   }
// }
// pub fn boolean_value_test(saved) {
//   let program = encode.from_json(saved)
//   assert Ok(mod) = fetch(program, "boolean")
//   assert Ok(true_mod) = fetch(mod, "True")
//   let #(typed, typer) = eyg.compile_unconstrained(true_mod, browser.harness())
//   assert Ok(type_) = typer.get_type(typed)
//   let type_ = t.resolve(type_, typer.substitutions)
//   let "True" = t.to_string(type_, browser.native_to_string)
// }
// pub fn some_value_test(saved) {
//   let program = encode.from_json(saved)
//   assert Ok(mod) = fetch(program, "option")
//   assert Ok(some) = fetch(mod, "Some")
//   let #(typed, typer) = eyg.compile_unconstrained(some, browser.harness())
//   assert Ok(type_) = typer.get_type(typed)
//   let type_ = t.resolve(type_, typer.substitutions)
//   let "1 -> Some 1" = t.to_string(type_, browser.native_to_string)
// }
// pub fn none_value_test(saved) {
//   let program = encode.from_json(saved)
//   assert Ok(mod) = fetch(program, "option")
//   assert Ok(none) = fetch(mod, "None")
//   let #(typed, typer) = eyg.compile_unconstrained(none, browser.harness())
//   assert Ok(type_) = typer.get_type(typed)
//   let type_ = t.resolve(type_, typer.substitutions)
//   let "None" = t.to_string(type_, browser.native_to_string)
// }
// pub fn boolean_not_test(saved) {
//   let program = encode.from_json(saved)
//   assert Ok(mod) = fetch(program, "boolean")
//   // Can't do this test because mod mean that True/False is not in scope
//   // assert Ok(not) = fetch(mod, "not")
//   let #(typed, typer) = eyg.compile_unconstrained(mod, browser.harness())
//   assert Ok(type_) = typer.get_type(typed)
//   let type_ = t.resolve(type_, typer.substitutions)
//   let "True" = t.to_string(type_, browser.native_to_string)
// }
// // pub fn and_test(saved) {
// //   let program = encode.from_json(saved)
// //   assert Ok(mod) = fetch(program, "boolean")
// //   assert Ok(and) = fetch(mod, "and")
// //   let #(typed, typer) = eyg.compile_unconstrained(and)
// //   assert Ok(type_) = typer.get_type(typed)
// //   let type_ = t.resolve(type_, typer.substitutions)
// //   let "True" = t.to_string(type_, browser.native_to_string)
// // }
// pub fn equal_test(saved) {
//   let program = encode.from_json(saved)
//   assert Ok(mod) = fetch(program, "boolean")
//   assert Ok(equal) = fetch(mod, "equal")
//   let #(typed, typer) = eyg.compile_unconstrained(equal, browser.harness())
//   assert Ok(type_) = typer.get_type(typed)
//   let type_ = t.resolve(type_, typer.substitutions)
//   let "(1, 1) -> True | False" = t.to_string(type_, browser.native_to_string)
// }
