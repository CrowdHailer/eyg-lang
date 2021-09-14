import gleam/io
import eyg/ast
import eyg/ast/edit.{Above, InsertLine}
import eyg/ast/expression as e
import eyg/ast/pattern as p

fn apply_edit(tree, action, path) {
  edit.apply_edit(tree, edit.Edit(action, path))
}

pub fn insert_line_above_test() {
  let tree = ast.tuple_([ast.binary("Hello")])
  let action = InsertLine(Above)

  let #(t1, p1) = apply_edit(tree, action, [])
  assert #(_, e.Let(p.Variable(""), value, then)) = t1
  assert True = value == ast.hole()
  assert True = then == tree
  assert [] = p1
  let #(t2, p2) = apply_edit(tree, action, [0])
  assert True = t1 == t2
  assert True = p1 == p2
}

pub fn insert_line_into_existing_let_test() {
  let tree = ast.let_(p.Variable("a"), ast.binary("A"), ast.tuple_([]))
  let action = InsertLine(Above)

  let #(t1, p1) = apply_edit(tree, action, [])
  assert #(_, e.Let(p.Variable(""), value, then)) = t1
  assert True = value == ast.hole()
  assert True = then == tree
  assert [] = p1
  let #(t2, p2) = apply_edit(tree, action, [0])
  assert True = t1 == t2
  assert True = p1 == p2
  let #(t3, p3) = apply_edit(tree, action, [1])
  assert #(_, e.Let(p.Variable("a"), value, then)) = t3
  assert True = value == ast.binary("A")
  assert #(_, e.Let(p.Variable(""), value, then)) = then
  assert True = value == ast.hole()
  assert #(_, e.Tuple([])) = then
  assert [1] = p3
}
