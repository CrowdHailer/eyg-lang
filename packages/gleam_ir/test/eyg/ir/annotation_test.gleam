import eyg/ir/tree as ir
import gleam/list

fn wide(depth) {
  case depth {
    0 -> ir.integer(1)
    _ -> ir.apply(wide(depth - 1), wide(depth - 1))
  }
}

pub fn a_wide_tree_can_be_annotated_test() {
  let source = wide(16)
  assert ir.map_annotation(source, fn(_) { 1 }) |> ir.clear_annotation == source
}

pub fn a_wide_tree_can_be_searched_test() {
  let source =
    ir.apply(wide(16), ir.apply(ir.builtin("int_add"), ir.package("standard")))
  assert ir.list_builtins(source) == ["int_add"]
  assert ir.list_references(source) == [ir.Package("standard")]
}

pub fn deep_trees_can_be_mapped_and_searched_test() {
  let source = deep(50_000, ir.integer(1))
  let mapped = ir.map_annotation(source, fn(_) { "mapped" })
  let annotations = ir.get_annotation(mapped)
  assert list.length(annotations) == 50_001
  assert list.all(annotations, fn(annotation) { annotation == "mapped" })
  assert ir.list_references(mapped) == []
  assert ir.list_builtins(mapped) == []
}

fn deep(remaining, tree) {
  case remaining {
    0 -> tree
    _ -> deep(remaining - 1, ir.lambda("x", tree))
  }
}

pub fn rewriting_preserves_child_order_and_transforms_leaves_test() {
  let source =
    ir.let_(
      "x",
      ir.integer(1),
      ir.apply(ir.lambda("y", ir.variable("x")), ir.integer(2)),
    )
  let mapped =
    ir.rewrite_pure(source, fn(node) {
      case node.0 {
        ir.Integer(n) -> #(ir.Integer(n + 10), "mapped")
        expression -> #(expression, "mapped")
      }
    })
  let expected =
    ir.let_(
      "x",
      ir.integer(11),
      ir.apply(ir.lambda("y", ir.variable("x")), ir.integer(12)),
    )
    |> ir.map_annotation(fn(_) { "mapped" })
  assert mapped == expected
}
