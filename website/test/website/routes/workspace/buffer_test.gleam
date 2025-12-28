import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/isomorphic as t
import gleam/option.{None}
import morph/editable as e
import morph/projection as p
import website/routes/workspace/buffer

pub fn types_of_list_items_test() {
  let projection = #(p.Exp(e.Vacant), [p.ListItem([e.Integer(1)], [], None)])
  let buffer = buffer.from_projection(projection, infer.pure())
  assert Ok(t.Integer) == buffer.target_type(buffer)
}

pub fn types_of_list_tail_test() {
  let projection = #(p.Exp(e.Vacant), [p.ListTail([e.Integer(1)])])
  let buffer = buffer.from_projection(projection, infer.pure())
  assert Ok(t.List(t.Integer)) == buffer.target_type(buffer)
}
