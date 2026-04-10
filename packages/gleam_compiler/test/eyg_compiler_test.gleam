import eyg/compiler
import gleeunit

pub fn main() -> Nil {
  let source = ir.let_("x", ir.integer(5), ir.variable("x"))
  let refs = dict.new()
  compiler.to_js(source, refs)
  |> echo
  gleeunit.main()
}

import eyg/ir/tree as ir
import gleam/dict
