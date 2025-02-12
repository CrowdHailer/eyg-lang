import eyg/editor/v1/app
import eygir/annotated as a
import gleeunit/should

pub fn call_test() {
  let source = a.let_("x", a.string("initial"), a.variable("x"))

  let initial = app.init(source)

  // update value of let
  let #(state, _cmd) = app.select_node(initial, [0])
  let #(state, _cmd) = app.keypress("w", state)
  a.let_("x", a.apply(a.vacant(), a.string("initial")), a.variable("x"))
  |> should.equal(state.source)

  // update final statement
  let #(state, _cmd) = app.select_node(initial, [1])
  let #(state, _cmd) = app.keypress("w", state)
  a.let_("x", a.string("initial"), a.apply(a.vacant(), a.variable("x")))
  |> should.equal(state.source)
}

pub fn insert_parameter_test() {
  // test variable
  let source = a.let_("_", a.variable("x"), a.vacant())
  let initial = app.init(source)

  let #(state, _cmd) = app.select_node(initial, [0])
  let #(state, _cmd) = app.keypress("i", state)
  let assert app.WriteLabel(initial, commit) = state.mode
  should.equal(initial, "x")
  a.let_("_", a.variable("foo"), a.vacant())
  |> should.equal(commit("foo"))

  // test lambdanested to test step and zip
  let source = a.lambda("x", a.lambda("y", a.vacant()))
  let initial = app.init(source)

  let #(state, _cmd) = app.select_node(initial, [0])
  let #(state, _cmd) = app.keypress("i", state)
  let assert app.WriteLabel(initial, commit) = state.mode
  should.equal(initial, "y")
  a.lambda("x", a.lambda("foo", a.vacant()))
  |> should.equal(commit("foo"))

  // test let
  let source =
    a.let_("_", a.let_("x", a.string("stuff"), a.vacant()), a.vacant())
  let initial = app.init(source)

  let #(state, _cmd) = app.select_node(initial, [0])
  let #(state, _cmd) = app.keypress("i", state)
  let assert app.WriteLabel(initial, commit) = state.mode
  should.equal(initial, "x")
  a.let_("_", a.let_("foo", a.string("stuff"), a.vacant()), a.vacant())
  |> should.equal(commit("foo"))
}
