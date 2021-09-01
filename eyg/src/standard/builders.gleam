import eyg/ast
import eyg/ast/pattern

pub fn function(args, body) {
  ast.function("$", ast.let_(pattern.tuple_(args), ast.variable("$"), body))
}

pub fn args_body(body) {
  let #(_, ast.Let(pattern.Tuple(args), #(_, ast.Variable("$")), body)) = body
  #(args, body)
}

pub fn clause(variant, variables, then) {
  #(variant, "$", ast.let_(pattern.tuple_(variables), ast.variable("$"), then))
}
