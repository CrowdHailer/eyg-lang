import eyg/ir/dag_json
import eyg/ir/tree
import gleam/int
import gleam/list
import gleam/option
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

pub fn pin_returns_metadata_and_releases_test() {
  let first = #(tree.Reference(tree.Package("a")), "first")
  let second = #(tree.Reference(tree.Version("b", 2)), "second")
  let source = #(tree.Apply(first, second), "root")
  let pin = fn(package, version) {
    let version = option.unwrap(version, 1)
    continuation.return(tree.Release(package, version, dag_json.vacant_cid))
  }
  let #(releases, source) = tree.pin(source, pin)(fn(x) { x })
  let assert #(tree.Apply(first, second), _) = source
  let first_pinned = tree.Release("a", 1, dag_json.vacant_cid)
  let second_pinned = tree.Release("b", 2, dag_json.vacant_cid)
  assert #(tree.Reference(tree.Pinned(first_pinned)), "first") == first
  assert #(tree.Reference(tree.Pinned(second_pinned)), "second") == second

  assert releases == [#("first", first_pinned), #("second", second_pinned)]
}

fn fs(files) {
  fn(path) { continuation.return(list.key_find(files, path)) }
}

fn fail(reason) {
  fn(_) { Error(reason) }
}

pub fn locate_relative_sources_test() {
  let source = tree.relative("lib/middle.eyg")
  let middle = tree.relative("../leaf.eyg")
  let leaf = tree.integer(1)
  let load =
    fs([
      #("/project/lib/middle.eyg", middle),
      #("/project/leaf.eyg", leaf),
    ])
  let assert Ok(#(located, source)) =
    tree.locate(source, "/project", load, fail)(Ok)
  let assert [#(middle_path, located_middle), #(leaf_path, located_leaf)] =
    located

  assert source == tree.relative("/project/lib/middle.eyg")
  assert leaf_path == "/project/leaf.eyg"
  assert located_leaf == leaf
  assert middle_path == "/project/lib/middle.eyg"
  assert located_middle == tree.relative("/project/leaf.eyg")
}

pub fn locate_deduplicates_sources_test() {
  let source =
    tree.apply(tree.relative("dependency.eyg"), tree.relative("dependency.eyg"))
  let dependency = tree.integer(1)
  let load = fn(_path) { continuation.return(Ok(dependency)) }
  let assert Ok(#(located, source)) =
    tree.locate(source, "/project", load, fail)(Ok)

  assert source
    == tree.apply(
      tree.relative("/project/dependency.eyg"),
      tree.relative("/project/dependency.eyg"),
    )
  assert located == [#("/project/dependency.eyg", dependency)]
}

pub fn fail_on_cycles_test() {
  let source = tree.relative("a.eyg")
  let load =
    fs([
      #("/project/a.eyg", tree.relative("b.eyg")),
      #("/project/b.eyg", tree.relative("a.eyg")),
    ])
  let assert Error(tree.ReferenceCycle(cycle)) =
    tree.locate(source, "/project", load, fail)(Ok)

  assert cycle
    == [
      "/project/a.eyg",
      "/project/b.eyg",
    ]
}
