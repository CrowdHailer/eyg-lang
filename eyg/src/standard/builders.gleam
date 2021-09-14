import eyg/ast
import eyg/ast/expression.{Let, Tuple, Variable}
import eyg/ast/pattern

pub fn clause(variant, variables, then) {
  #(variant, "$", ast.let_(pattern.tuple_(variables), ast.variable("$"), then))
}
