import eyg/ir/tree as ir
import gleeunit/should
import morph/editable as et

fn should_equal(given, expected) {
  should.equal(given, expected)
  given
}

pub fn call_test() {
  let source =
    ir.apply(ir.apply(ir.variable("f"), ir.integer(1)), ir.integer(2))
  source
  |> et.from_annotated
  |> should_equal(et.Call(et.Variable("f"), [et.Integer(1), et.Integer(2)]))
  |> et.to_annotated([])
  |> ir.clear_annotation()
  |> should_equal(source)
}

pub fn destructure_test() {
  let source =
    ir.lambda(
      "$",
      ir.let_(
        "a",
        ir.apply(ir.select("foo"), ir.variable("$")),
        ir.variable("a"),
      ),
    )
  source
  |> et.from_annotated
  |> should_equal(et.Function(
    [et.Destructure([#("foo", "a")])],
    et.Variable("a"),
  ))
  |> et.to_annotated([])
  |> ir.clear_annotation()
  |> should_equal(source)
}

pub fn dont_destructure_used_test() {
  let source =
    ir.lambda(
      "x",
      ir.let_(
        "a",
        ir.apply(ir.select("foo"), ir.variable("x")),
        ir.variable("x"),
      ),
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
  |> ir.clear_annotation()
  |> should_equal(source)
}

pub fn call_select_test() {
  let source =
    ir.apply(
      ir.apply(ir.select("to_string"), ir.variable("integer")),
      ir.integer(5),
    )
  source
  |> et.from_annotated
  |> should_equal(
    et.Call(et.Select(et.Variable("integer"), "to_string"), [et.Integer(5)]),
  )
  |> et.to_annotated([])
  |> ir.clear_annotation()
  |> should_equal(source)
}

pub fn bare_select_test() {
  let source = ir.select("foo")
  source
  |> et.from_annotated
  |> should_equal(et.Function(
    [et.Bind("$")],
    et.Select(et.Variable("$"), "foo"),
  ))
  |> et.to_annotated([])
  |> ir.clear_annotation()
  |> should_equal(source)
}

pub fn unbound_case_test() {
  let source =
    ir.apply(
      ir.apply(ir.case_("Ok"), ir.vacant()),
      ir.lambda("x", ir.variable("x")),
    )
  source
  |> et.from_annotated
  // |> should_equal(
  //   et.Call(et.Select(et.Variable("integer"), "to_string"), [et.Integer(5)]),
  // )
  |> et.to_annotated([])
  |> ir.clear_annotation()
  |> should_equal(source)
}
