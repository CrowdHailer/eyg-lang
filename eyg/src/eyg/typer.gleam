import gleam/list
import eyg/ast.{Binary, Row, Tuple}
import eyg/typer/monotype

pub fn init() {
  Nil
}

fn infer_field(field, typer) {
  let #(name, tree) = field
  try #(type_, typer) = infer(tree, typer)
  Ok(#(#(name, type_), typer))
}

pub fn infer(
  tree: ast.Node,
  typer: Nil,
) -> Result(#(monotype.Monotype, Nil), Nil) {
  case tree {
    Binary(_) -> Ok(#(monotype.Binary, typer))
    Tuple(elements) -> {
      try #(types, typer) = list.try_map_state(elements, typer, infer)
      Ok(#(monotype.Tuple(types), typer))
    }
    Row(fields) -> {
      try #(types, typer) = list.try_map_state(fields, typer, infer_field)
      Ok(#(monotype.Row(types), typer))
    }
  }
}
