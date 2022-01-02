import gleam/io
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/ast/encode
import eyg/typer
import eyg/typer/monotype as t

// NOTE this relies on label being defined only once
fn fetch(tree, label) {
  let #(_, expression) = tree
  case expression {
    e.Let(p.Variable(l), value, _) if l == label -> Ok(value)
    e.Let(_, _, then) -> fetch(then, label)
    _ -> Error(Nil)
  }
}

// TODO print the type needed in a hole
// TODO There is an error when using in scope a some type, only happening on let rec statements
pub fn boolean_value_test(saved) {
  let program = encode.from_json(saved)
  let Ok(mod) = fetch(program, "boolean")
  let Ok(true) = fetch(mod, "True")
  let #(typed, typer) = typer.infer_unconstrained(true)
  let Ok(type_) = typer.get_type(typed)
  let type_ = t.resolve(type_, typer.substitutions)
  let "True" = t.to_string(type_)
}

pub fn some_value_test(saved) {
  let program = encode.from_json(saved)
  let Ok(mod) = fetch(program, "option")
  let Ok(some) = fetch(mod, "Some")
  let #(typed, typer) = typer.infer_unconstrained(some)
  let Ok(type_) = typer.get_type(typed)
  let type_ = t.resolve(type_, typer.substitutions)
  let "1 -> Some 1" = t.to_string(type_)
}

pub fn none_value_test(saved) {
  let program = encode.from_json(saved)
  let Ok(mod) = fetch(program, "option")
  let Ok(none) = fetch(mod, "None")
  let #(typed, typer) = typer.infer_unconstrained(none)
  let Ok(type_) = typer.get_type(typed)
  let type_ = t.resolve(type_, typer.substitutions)
  let "None" = t.to_string(type_)
}

// pub fn boolean_not_test(saved) {
//   let program = encode.from_json(saved)
//   let Ok(mod) = fetch(program, "boolean")
//   //   let Ok(true) = fetch(mod, "x")
//   let #(typed, typer) = typer.infer_unconstrained(mod)
//   let Ok(type_) = typer.get_type(typed)
//   let type_ = t.resolve(type_, typer.substitutions)
//   //   "{True: () -> 6, False: () -> 7} -> 2 -> 2"}"
//   let "True" = t.to_string(type_)
// }
pub fn and_test(saved) {
  let program = encode.from_json(saved)
  let Ok(mod) = fetch(program, "boolean")
  let Ok(and) = fetch(mod, "and")
  let #(typed, typer) = typer.infer_unconstrained(and)
  let Ok(type_) = typer.get_type(typed)
  let type_ = t.resolve(type_, typer.substitutions)
  let "True" = t.to_string(type_)
}

pub fn equal_test(saved) {
  let program = encode.from_json(saved)
  let Ok(mod) = fetch(program, "boolean")
  let Ok(equal) = fetch(mod, "equal")
  let #(typed, typer) = typer.infer_unconstrained(equal)
  let Ok(type_) = typer.get_type(typed)
  let type_ = t.resolve(type_, typer.substitutions)
  let "(1, 1) -> True | False" = t.to_string(type_)
}
