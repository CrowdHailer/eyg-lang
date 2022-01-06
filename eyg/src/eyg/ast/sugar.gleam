import gleam/list
import gleam/option.{None, Some}
import eyg/ast/expression as e
import eyg/ast/pattern as p
import eyg/typer

// pub type Element {
//   UnitVariant(
//     label: String,
//     then: e.Expression(typer.Metadata, e.Expression(typer.Metadata, Nil)),
//   )
//   TupleVariant(
//     label: String,
//     parameters: List(String),
//     then: e.Expression(typer.Metadata, e.Expression(typer.Metadata, Nil)),
//   )
// }
// by convention change the highest level key i.e. name in pattern follows through to name in calls.
pub fn match(tree) {
  case tree {
    // TODO undo this
    //   e.Let(
    //     p.Variable(n1),
    //     #(
    //       _,
    //       e.Function(
    //         p.Row([#(n2, "then")]),
    //         #(_, e.Call(#(_, e.Variable("then")), #(_, e.Tuple([])))),
    //       ),
    //     ),
    //     then,
    //   ) if n1 == n2 -> Ok(UnitVariant(n1, then))
    //   e.Let(
    //     p.Variable(n1),
    //     #(
    //       _,
    //       e.Function(
    //         p.Tuple(elements),
    //         #(
    //           _,
    //           e.Function(
    //             p.Row([#(n2, "then")]),
    //             #(_, e.Call(#(_, e.Variable("then")), #(_, e.Tuple(e_call)))),
    //           ),
    //         ),
    //       ),
    //     ),
    //     then,
    //   ) if n1 == n2 -> {
    //     try parameters = all_elements_named(elements)
    //     try calls = all_elements_variables(e_call)
    //     case parameters == calls {
    //       True -> Ok(TupleVariant(n1, parameters, then))
    //       False -> Error(Nil)
    //     }
    //   }
    _ -> Error(Nil)
  }
}

fn all_elements_named(elements) {
  list.try_map(
    elements,
    fn(e) {
      case e {
        Some(v) -> Ok(v)
        None -> Error(Nil)
      }
    },
  )
}

fn all_elements_variables(elements) {
  list.try_map(
    elements,
    fn(e) {
      case e {
        #(_, e.Variable(x)) -> Ok(x)
        _ -> Error(Nil)
      }
    },
  )
}
