import eyg/ast/expression as e
import eyg/ast/pattern as p

// extend sugar to dot syntax
// add expression information to pattern and pattern values. this will allow doing some is_sugar on the resulting expression
// by convention change the highest level key i.e. name in pattern follows through to name in calls.
// investigate keyboard short cut to use create these patterns
// things like rows in case I think we can do a down function that suggests the next un chosed key name actually this won't happen that often
// for example list reverse doesn't know that it's a list until you have both cases defined
// is_unit_variant
// is_tuple_variant
// is_row_variant
// row variant always beause variables always have a name
// Do an is_sugar and return the enum
// put dot access in the example
// check updating
// Does this go along side remove the tabindex= -1 I don't think so.
// change type -> tagged tag name in syntax
pub fn is_variant(tree) {
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
      _then,
    ) if n1 == n2 -> True
    _ -> False
  }
}

pub fn is_data_variant(tree) {
  case tree {
    e.Let(
      p.Variable(n1),
      #(
        _,
        e.Function(
          p.Tuple(_),
          #(
            _,
            e.Function(
              p.Row([#(n2, "then")]),
              #(_, e.Call(#(_, e.Variable("then")), #(_, e.Tuple(_)))),
            ),
          ),
        ),
      ),
      _then,
    ) if n1 == n2 -> True
    _ -> False
  }
}
