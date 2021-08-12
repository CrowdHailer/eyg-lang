import gleam/list
import gleam/string
import language/ast.{Assignment as PVar}

pub fn seq(assignments, final) {
  case assignments {
    [] -> final
    [#(pattern, value), ..assignments] -> #(
      Nil,
      ast.Let(pattern, value, seq(assignments, final)),
    )
  }
}

pub fn test(name, assignments, final) {
  fun(string.concat([name, "_test"]), [], assignments, final)
}

// named function
pub fn fun(name: String, for, assignments, final) {
  #(PVar(name), function(for, seq(assignments, final)))
}

fn function(for, in) {
  #(Nil, ast.Fn(list.map(for, fn(name) { #(Nil, name) }), in))
}

pub fn vars(labels) {
  list.map(labels, var)
}

pub fn var(name) {
  #(Nil, ast.Var(name))
}

pub fn call(function, with) {
  #(Nil, ast.Call(function, with))
}

pub fn label_call(function, with) {
  call(var(function), vars(with))
}
