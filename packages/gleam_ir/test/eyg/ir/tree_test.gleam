import eyg/ir/tree
import gleam/int
import gleam/list
import midas/continuation

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

fn print(exp: tree.Expression(_)) {
  case exp {
    tree.Variable(label:) -> "Variable: " <> label
    tree.Lambda(label:, body: _) -> "Lambda: " <> label
    tree.Apply(func: _, argument: _) -> "Apply"
    tree.Let(label:, definition: _, body: _) -> "Let: " <> label
    tree.Integer(value:) -> "Integer: " <> int.to_string(value)
    _ -> ""
  }
}

fn identity(x) {
  x
}

pub fn map_children_test() {
  let #(exp, _) =
    tree.let_(
      "x",
      tree.apply(tree.variable("a"), tree.integer(1)),
      tree.lambda("f", tree.integer(2)),
    )
  assert exp
    == tree.map_children(exp, fn(node) { continuation.return(node) })(identity)
}

pub fn fold_test() {
  let node =
    tree.let_(
      "x",
      tree.apply(tree.variable("a"), tree.integer(1)),
      tree.lambda("f", tree.integer(2)),
    )
  let nodes =
    tree.fold(node, [], fn(acc, node) {
      continuation.return([print(node.0), ..acc])
    })(list.reverse)
  assert [
      "Let: x",
      "Apply",
      "Variable: a",
      "Integer: 1",
      "Lambda: f",
      "Integer: 2",
    ]
    == nodes
}

pub fn fold_post_order_test() {
  let node =
    tree.let_(
      "x",
      tree.apply(tree.variable("a"), tree.integer(1)),
      tree.lambda("f", tree.integer(2)),
    )
  let nodes =
    tree.fold_post_order(node, [], fn(acc, node) {
      continuation.return([print(node.0), ..acc])
    })(list.reverse)
  assert [
      "Variable: a",
      "Integer: 1",
      "Apply",
      "Integer: 2",
      "Lambda: f",
      "Let: x",
    ]
    == nodes
}

pub fn rewite_test() {
  let node =
    tree.let_(
      "x",
      tree.apply(tree.variable("a"), tree.integer(1)),
      tree.lambda("f", tree.integer(2)),
    )
  assert node == tree.rewrite(node, continuation.return)(identity)
}

pub fn rewrite_apply_test() {
  let node = tree.apply(tree.lambda("x", tree.variable("x")), tree.integer(1))

  let remove = fn(node) {
    let #(exp, _meta) = node
    case exp {
      tree.Apply(#(tree.Lambda(param, #(tree.Variable(var), _)), _), value)
        if param == var
      -> continuation.return(value)
      _ -> continuation.return(node)
    }
  }
  assert tree.integer(1) == tree.rewrite(node, remove)(identity)
}

pub fn rewrite_with_order_test() {
  let node =
    tree.let_(
      "x",
      tree.apply(tree.variable("a"), tree.integer(1)),
      tree.lambda("f", tree.integer(2)),
    )
  let #(nodes, rewritten) =
    tree.rewrite_with(node, [], fn(nodes, node) {
      continuation.return(#([print(node.0), ..nodes], node))
    })(identity)

  assert rewritten == node
  assert list.reverse(nodes)
    == [
      "Variable: a",
      "Integer: 1",
      "Apply",
      "Integer: 2",
      "Lambda: f",
      "Let: x",
    ]
}

pub fn rewrite_with_metadata_test() {
  let node = tree.apply(tree.variable("f"), tree.integer(1))
  let #(count, rewritten) =
    tree.rewrite_with(node, 0, fn(id, node) {
      let #(exp, _meta) = node
      continuation.return(#(id + 1, #(exp, id)))
    })(identity)
  let assert #(tree.Apply(function, argument), apply_id) = rewritten

  assert function.1 == 0
  assert argument.1 == 1
  assert apply_id == 2
  assert count == 3
}
