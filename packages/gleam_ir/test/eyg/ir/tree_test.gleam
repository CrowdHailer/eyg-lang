import eyg/ir/dag_json
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

pub fn reference_helpers_test() {
  let cid = dag_json.vacant_cid

  assert #(tree.Reference(tree.Content(cid)), Nil) == tree.reference(cid)
  assert #(tree.Reference(tree.Package("standard")), Nil)
    == tree.package("standard")
  assert #(tree.Reference(tree.Version("standard", 3)), Nil)
    == tree.version("standard", 3)
  assert #(tree.Reference(tree.Pinned(tree.Release("standard", 3, cid))), Nil)
    == tree.release("standard", 3, cid)
  assert #(tree.Reference(tree.Relative("./module.eyg")), Nil)
    == tree.relative("./module.eyg")
}

pub fn reference_lists_test() {
  let cid = dag_json.vacant_cid
  let source =
    tree.list([
      tree.reference(cid),
      tree.package("standard"),
      tree.version("standard", 3),
      tree.release("standard", 3, cid),
      tree.relative("./module.eyg"),
    ])

  assert [
      tree.Content(cid),
      tree.Package("standard"),
      tree.Version("standard", 3),
      tree.Pinned(tree.Release("standard", 3, cid)),
      tree.Relative("./module.eyg"),
    ]
    == tree.list_references(source)
  assert [cid] == tree.list_content_references(source)
  assert [tree.Release("standard", 3, cid)]
    == tree.list_named_references(source)
}

pub fn map_release_test() {
  let cid = dag_json.vacant_cid
  let source =
    tree.list([
      tree.version("standard", 3),
      tree.release("standard", 3, cid),
    ])

  assert tree.list([
      tree.version("standard", 3),
      tree.release("renamed", 4, cid),
    ])
    == tree.map_release(source, fn(_) { tree.Release("renamed", 4, cid) })
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
