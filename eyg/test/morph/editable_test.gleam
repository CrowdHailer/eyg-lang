import eygir/annotated as a
import gleeunit/should
import morph/editable as et

fn should_equal(given, expected) {
  should.equal(given, expected)
  given
}

pub fn call_test() {
  let source = a.apply(a.apply(a.variable("f"), a.integer(1)), a.integer(2))
  source
  |> et.from_annotated
  |> should_equal(et.Call(et.Variable("f"), [et.Integer(1), et.Integer(2)]))
  |> et.to_annotated([])
  |> a.clear_annotation()
  |> should_equal(source)
}

pub fn destructure_test() {
  let source =
    a.lambda(
      "$",
      a.let_("a", a.apply(a.select("foo"), a.variable("$")), a.variable("a")),
    )
  source
  |> et.from_annotated
  |> should_equal(et.Function(
    [et.Destructure([#("foo", "a")])],
    et.Variable("a"),
  ))
  |> et.to_annotated([])
  |> a.clear_annotation()
  |> should_equal(source)
}

pub fn dont_destructure_used_test() {
  let source =
    a.lambda(
      "x",
      a.let_("a", a.apply(a.select("foo"), a.variable("x")), a.variable("x")),
    )
  source
  |> et.from_annotated
  |> should_equal(et.Function(
    [et.Bind("x")],
    et.Block(
      [#(et.Bind("a"), et.Select(et.Variable("x"), "foo"))],
      et.Variable("x"),
      False,
    ),
  ))
  |> et.to_annotated([])
  |> a.clear_annotation()
  |> should_equal(source)
}

pub fn call_select_test() {
  let source =
    a.apply(a.apply(a.select("to_string"), a.variable("integer")), a.integer(5))
  source
  |> et.from_annotated
  |> should_equal(
    et.Call(et.Select(et.Variable("integer"), "to_string"), [et.Integer(5)]),
  )
  |> et.to_annotated([])
  |> a.clear_annotation()
  |> should_equal(source)
}

pub fn bare_select_test() {
  let source = a.select("foo")
  source
  |> et.from_annotated
  |> should_equal(et.Function(
    [et.Bind("$")],
    et.Select(et.Variable("$"), "foo"),
  ))
  |> et.to_annotated([])
  |> a.clear_annotation()
  |> should_equal(source)
}

pub fn unbound_case_test() {
  let source =
    a.apply(a.apply(a.case_("Ok"), a.vacant()), a.lambda("x", a.variable("x")))
  source
  |> et.from_annotated
  // |> should_equal(
  //   et.Call(et.Select(et.Variable("integer"), "to_string"), [et.Integer(5)]),
  // )
  |> et.to_annotated([])
  |> a.clear_annotation()
  |> should_equal(source)
}
