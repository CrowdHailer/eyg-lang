import eyg/ir/tree

pub fn lambda_free_variable_test() {
  let node = tree.lambda("y", tree.variable("f"))
  assert ["f"] == tree.free_variables(node, [])
}

pub fn lambda_shadowing_test() {
  let node = tree.lambda("x", tree.lambda("y", tree.variable("x")))
  assert [] == tree.free_variables(node, [])
}

pub fn free_in_let_definition_test() {
  let node = tree.let_("x", tree.variable("f"), tree.variable("x"))
  assert ["f"] == tree.free_variables(node, [])
}

pub fn free_in_let_then_test() {
  let node = tree.let_("x", tree.variable("x"), tree.variable("y"))
  assert ["x", "y"] == tree.free_variables(node, [])
}

pub fn nested_let_then_test() {
  let node =
    tree.let_(
      "x",
      tree.variable("a"),
      tree.let_("x", tree.variable("b"), tree.variable("x")),
    )
  assert ["a", "b"] == tree.free_variables(node, [])
}

pub fn apply_order_test() {
  let node = tree.apply(tree.variable("a"), tree.variable("b"))
  assert ["a", "b"] == tree.free_variables(node, [])
}

pub fn ignore_if_given_in_env_test() {
  let node = tree.variable("a")
  assert [] == tree.free_variables(node, ["a"])
}
