import eyg/editor/v1/app
import eyg/ir/tree as ir
import gleeunit/should

pub fn call_test() {
  let source = ir.let_("x", ir.string("initial"), ir.variable("x"))

  let initial = app.init(source)

  // update value of let
  let #(state, _cmd) = app.select_node(initial, [0])
  let #(state, _cmd) = app.keypress("w", state)
  ir.let_("x", ir.apply(ir.vacant(), ir.string("initial")), ir.variable("x"))
  |> should.equal(state.source)

  // update final statement
  let #(state, _cmd) = app.select_node(initial, [1])
  let #(state, _cmd) = app.keypress("w", state)
  ir.let_("x", ir.string("initial"), ir.apply(ir.vacant(), ir.variable("x")))
  |> should.equal(state.source)
}

pub fn insert_parameter_test() {
  // test variable
  let source = ir.let_("_", ir.variable("x"), ir.vacant())
  let initial = app.init(source)

  let #(state, _cmd) = app.select_node(initial, [0])
  let #(state, _cmd) = app.keypress("i", state)
  let assert app.WriteLabel(initial, commit) = state.mode
  should.equal(initial, "x")
  ir.let_("_", ir.variable("foo"), ir.vacant())
  |> should.equal(commit("foo"))

  // test lambdanested to test step and zip
  let source = ir.lambda("x", ir.lambda("y", ir.vacant()))
  let initial = app.init(source)

  let #(state, _cmd) = app.select_node(initial, [0])
  let #(state, _cmd) = app.keypress("i", state)
  let assert app.WriteLabel(initial, commit) = state.mode
  should.equal(initial, "y")
  ir.lambda("x", ir.lambda("foo", ir.vacant()))
  |> should.equal(commit("foo"))

  // test let
  let source =
    ir.let_("_", ir.let_("x", ir.string("stuff"), ir.vacant()), ir.vacant())
  let initial = app.init(source)

  let #(state, _cmd) = app.select_node(initial, [0])
  let #(state, _cmd) = app.keypress("i", state)
  let assert app.WriteLabel(initial, commit) = state.mode
  should.equal(initial, "x")
  ir.let_("_", ir.let_("foo", ir.string("stuff"), ir.vacant()), ir.vacant())
  |> should.equal(commit("foo"))
}
