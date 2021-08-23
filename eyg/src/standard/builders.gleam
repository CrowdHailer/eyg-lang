import eyg/ast
import eyg/ast/pattern

pub fn function(args, body) {
  ast.Function("$", ast.Let(pattern.Tuple(args), ast.Variable("$"), body))
}

pub fn clause(variant, variables, then) {
  #(variant, "$", ast.Let(pattern.Tuple(variables), ast.Variable("$"), then))
}
