import gleam/list
import eyg/ast
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/typer

// Union is a set of variants a variant can be tag or tagged data
// The sugar is for Tag or Tag Constructor
pub type Sugar(m, n) {
  Tagged(name: String, expression: e.Expression(m, n))
}

// In a call Option(Nil) it's not the constructor called as such that's normal function
// Dark blue is because Tag
// don't need constructors in scope as that's a name and we can create in literal with name
// function constuctors can be more targets at adding extra rules
// TODO remove
pub fn tagged(name, expression) {
  ast.function(
    p.Record([#(name, "then")]),
    ast.call(ast.variable("then"), expression),
  )
}

pub fn match(tree) {
  case tree {
    e.Function(
      p.Record([#(name, "then")]),
      #(_, e.Call(#(_, e.Variable("then")), expression)),
    ) -> Ok(Tagged(name, expression))
    _ -> Error(Nil)
  }
}
