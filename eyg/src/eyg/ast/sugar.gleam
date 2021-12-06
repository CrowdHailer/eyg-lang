import gleam/list
import gleam/option.{None, Some}
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/typer

pub type Element {
  UnitVariant(label: String, then: e.Expression(typer.Metadata))
  TupleVariant(
    label: String,
    parameters: List(String),
    then: e.Expression(typer.Metadata),
  )
}

// by convention change the highest level key i.e. name in pattern follows through to name in calls.
pub fn match(tree) {
  case tree {
    e.Let(
      p.Variable(n1),
      #(
        _,
        e.Function(
          p.Row([#(n2, "then")]),
          #(_, e.Call(#(_, e.Variable("then")), #(_, e.Tuple([])))),
        ),
      ),
      then,
    ) if n1 == n2 -> Ok(UnitVariant(n1, then))
    e.Let(
      p.Variable(n1),
      #(
        _,
        e.Function(
          p.Tuple(elements),
          #(
            _,
            e.Function(
              p.Row([#(n2, "then")]),
              #(_, e.Call(#(_, e.Variable("then")), #(_, e.Tuple(_)))),
            ),
          ),
        ),
      ),
      then,
    ) if n1 == n2 -> {
      let parameters =
        list.fold(
          elements,
          [],
          fn(e, acc) {
            case e {
              Some(p) -> [p, ..acc]
              None -> acc
            }
          },
        )
      Ok(TupleVariant(n1, parameters, then))
    }
    _ -> Error(Nil)
  }
}
