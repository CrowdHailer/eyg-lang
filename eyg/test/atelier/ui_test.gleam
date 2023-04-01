import gleeunit/should
import eygir/expression as e
import atelier/app

pub fn call_test() {
  let source = e.Let("x", e.Binary("initial"), e.Variable("x"))
  let initial = app.init(source)

  // update value of let
  let #(state, _cmd) = app.select_node(initial, [0])
  let #(state, _cmd) = app.keypress("w", state)
  e.Let("x", e.Apply(e.Vacant(""), e.Binary("initial")), e.Variable("x"))
  |> should.equal(state.source)

  // update final statement
  let #(state, _cmd) = app.select_node(initial, [1])
  let #(state, _cmd) = app.keypress("w", state)
  e.Let("x", e.Binary("initial"), e.Apply(e.Vacant(""), e.Variable("x")))
  |> should.equal(state.source)
}

pub fn insert_parameter_test() {
  // test variable
  let source = e.Let("_", e.Variable("x"), e.Vacant(""))
  let initial = app.init(source)

  let #(state, _cmd) = app.select_node(initial, [0])
  let #(state, _cmd) = app.keypress("i", state)
  let assert app.WriteLabel(initial, commit) = state.mode
  should.equal(initial, "x")
  e.Let("_", e.Variable("foo"), e.Vacant(""))
  |> should.equal(commit("foo"))

  // test lambdanested to test step and zip
  let source = e.Lambda("x", e.Lambda("y", e.Vacant("")))
  let initial = app.init(source)

  let #(state, _cmd) = app.select_node(initial, [0])
  let #(state, _cmd) = app.keypress("i", state)
  let assert app.WriteLabel(initial, commit) = state.mode
  should.equal(initial, "y")
  e.Lambda("x", e.Lambda("foo", e.Vacant("")))
  |> should.equal(commit("foo"))

  // test let
  let source =
    e.Let("_", e.Let("x", e.Binary("stuff"), e.Vacant("")), e.Vacant(""))
  let initial = app.init(source)

  let #(state, _cmd) = app.select_node(initial, [0])
  let #(state, _cmd) = app.keypress("i", state)
  let assert app.WriteLabel(initial, commit) = state.mode
  should.equal(initial, "x")
  e.Let("_", e.Let("foo", e.Binary("stuff"), e.Vacant("")), e.Vacant(""))
  |> should.equal(commit("foo"))
}
