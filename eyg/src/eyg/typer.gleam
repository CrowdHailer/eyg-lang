import gleam/list
import eyg/ast.{Binary, Tuple}
import eyg/typer/monotype

pub fn init() {
  Nil
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
  }
}
