import eyg/interpreter/value as v
import eyg/ir/tree as ir
import touch_grass/eyg_parse

pub fn encode_error_is_a_result_test() {
  assert eyg_parse.encode(Error("bad syntax"))
    == v.error(v.String("bad syntax"))
}

pub fn encode_flattens_a_leaf_test() {
  let assert v.Tagged("Ok", v.LinkedList(nodes)) =
    eyg_parse.encode(Ok(ir.integer(42)))
  assert nodes == [v.Tagged("Integer", v.Integer(42))]
}

pub fn encode_flattens_children_in_preorder_test() {
  let node = ir.let_("x", ir.integer(0), ir.variable("x"))
  let assert v.Tagged("Ok", v.LinkedList(nodes)) = eyg_parse.encode(Ok(node))
  assert nodes
    == [
      v.Tagged("Let", v.String("x")),
      v.Tagged("Integer", v.Integer(0)),
      v.Tagged("Variable", v.String("x")),
    ]
}

pub fn encode_flattens_application_arguments_test() {
  let node = ir.apply(ir.variable("f"), ir.variable("a"))
  let assert v.Tagged("Ok", v.LinkedList(nodes)) = eyg_parse.encode(Ok(node))
  assert nodes
    == [
      v.Tagged("Apply", v.unit()),
      v.Tagged("Variable", v.String("f")),
      v.Tagged("Variable", v.String("a")),
    ]
}
