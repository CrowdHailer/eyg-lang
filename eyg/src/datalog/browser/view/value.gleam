import datalog/ast
import gleam/int
import lustre/attribute.{class}
import lustre/element.{text}
import lustre/element/html.{span}

pub fn render(value) {
  case value {
    ast.B(True) -> text("true")
    ast.B(False) -> text("false")
    ast.I(i) -> text(int.to_string(i))
    ast.S(s) -> span([], [text("\""), text(s), text("\"")])
  }
}
