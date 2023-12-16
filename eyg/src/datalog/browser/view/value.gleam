import gleam/int
import lustre/element.{text}
import datalog/ast

pub fn render(value) {
  case value {
    ast.B(True) -> text("true")
    ast.B(False) -> text("false")
    ast.I(i) -> text(int.to_string(i))
    ast.S(s) -> text(s)
  }
}
