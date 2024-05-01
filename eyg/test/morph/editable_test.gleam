import eygir/annotated as a
import eygir/expression as e
import gleeunit/should
import morph/editable as et

fn should_equal(given, expected) {
  should.equal(given, expected)
  given
}

pub fn call_test() {
  let source = e.Apply(e.Apply(e.Variable("f"), e.Integer(1)), e.Integer(2))
  source
  |> a.add_annotation(Nil)
  |> et.from_annotated
  |> should_equal(et.Call(et.Variable("f"), [et.Integer(1), et.Integer(2)]))
  |> et.to_expression
  |> should_equal(source)
}

pub fn destructure_test() {
  let source =
    e.Lambda(
      "$",
      e.Let("a", e.Apply(e.Select("foo"), e.Variable("$")), e.Variable("a")),
    )
  source
  |> a.add_annotation(Nil)
  |> et.from_annotated
  |> should_equal(et.Function(
    [et.Destructure([#("foo", "a")])],
    et.Variable("a"),
  ))
  |> et.to_expression
  |> should_equal(source)
}

pub fn dont_destructure_used_test() {
  let source =
    e.Lambda(
      "x",
      e.Let("a", e.Apply(e.Select("foo"), e.Variable("x")), e.Variable("x")),
    )
  source
  |> a.add_annotation(Nil)
  |> et.from_annotated
  |> should_equal(et.Function(
    [et.Bind("x")],
    et.Block(
      [#(et.Bind("a"), et.Select(et.Variable("x"), "foo"))],
      et.Variable("x"),
      False,
    ),
  ))
  |> et.to_expression
  |> should_equal(source)
}

pub fn call_select_test() {
  let source =
    e.Apply(e.Apply(e.Select("to_string"), e.Variable("integer")), e.Integer(5))
  source
  |> a.add_annotation(Nil)
  |> et.from_annotated
  |> should_equal(
    et.Call(et.Select(et.Variable("integer"), "to_string"), [et.Integer(5)]),
  )
  |> et.to_expression
  |> should_equal(source)
}

pub fn bare_select_test() {
  let source = e.Select("foo")
  source
  |> a.add_annotation(Nil)
  |> et.from_annotated
  |> should_equal(et.Function(
    [et.Bind("$")],
    et.Select(et.Variable("$"), "foo"),
  ))
  |> et.to_expression
  |> should_equal(source)
}

pub fn unbound_case_test() {
  let source =
    e.Apply(e.Apply(e.Case("Ok"), e.Vacant("")), e.Lambda("x", e.Variable("x")))
  source
  |> a.add_annotation(Nil)
  |> et.from_annotated
  // |> should_equal(
  //   et.Call(et.Select(et.Variable("integer"), "to_string"), [et.Integer(5)]),
  // )
  |> et.to_expression
  |> should_equal(source)
}
