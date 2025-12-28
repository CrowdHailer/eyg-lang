import eyg/analysis/type_/isomorphic as t
import gleam/option.{None}
import morph/editable as e
import morph/projection as p
import website/routes/workspace/state

pub fn types_of_list_items_test() {
  let projection = #(p.Exp(e.Vacant), [p.ListItem([e.Integer(1)], [], None)])
  assert Ok(t.Integer) == state.target_type(projection)
}

pub fn types_of_list_tail_test() {
  let projection = #(p.Exp(e.Vacant), [p.ListTail([e.Integer(1)])])
  assert Ok(t.List(t.Integer)) == state.target_type(projection)
}
