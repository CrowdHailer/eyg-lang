import eyg/ast
import eyg/ast/expression.{Let, Tuple, Variable}
import eyg/ast/pattern

pub fn function(args, body) {
  ast.function("$", ast.let_(pattern.tuple_(args), ast.variable("$"), body))
}

pub fn call(func, with_) {
  ast.call(func, ast.tuple_(with_))
}

pub fn args_body(body) {
  let #(_, Let(pattern.Tuple(args), #(_, Variable("$")), body)) = body
  #(args, body)
}

pub fn clause(variant, variables, then) {
  #(variant, "$", ast.let_(pattern.tuple_(variables), ast.variable("$"), then))
}
