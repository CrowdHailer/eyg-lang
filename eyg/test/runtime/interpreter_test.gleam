import gleam/string
import gleeunit/should
import eygir/expression as e
import eyg/runtime/interpreter as r

fn id(x) {
  r.Value(x)
}

pub fn variable_test() {
  let source = e.Variable("x")
  r.eval(source, [#("x", r.Binary("assigned"))], id)
  |> should.equal(r.Value(r.Binary("assigned")))
}

pub fn function_test() {
  let body = e.Variable("x")
  let source = e.Lambda("x", body)
  let env = [#("foo", r.Binary("assigned"))]
  r.eval(source, env, id)
  |> should.equal(r.Value(r.Function("x", body, env)))
}

pub fn function_application_test() {
  let source = e.Apply(e.Lambda("x", e.Binary("body")), e.Integer(0))
  r.eval(source, [], id)
  |> should.equal(r.Value(r.Binary("body")))

  let source =
    e.Let(
      "id",
      e.Lambda("x", e.Variable("x")),
      e.Apply(e.Variable("id"), e.Integer(0)),
    )
  r.eval(source, [], id)
  |> should.equal(r.Value(r.Integer(0)))
}

pub fn builtin_application_test() {
  let source = e.Apply(e.Variable("reverse"), e.Binary("hello"))
  let f = fn(x) {
    assert r.Binary(value) = x
    r.Value(r.Binary(string.reverse(value)))
  }
  r.eval(source, [#("reverse", r.Builtin(f))], id)
  |> should.equal(r.Value(r.Binary("olleh")))
}

// primitive
pub fn create_a_binary_test() {
  let source = e.Binary("hello")
  r.eval(source, [], id)
  |> should.equal(r.Value(r.Binary("hello")))
}

pub fn create_an_integer_test() {
  let source = e.Integer(5)
  r.eval(source, [], id)
  |> should.equal(r.Value(r.Integer(5)))
}

pub fn record_creation_test() {
  let source = e.Empty
  r.eval(source, [], id)
  |> should.equal(r.Value(r.Record([])))

  let source =
    e.Apply(
      e.Apply(e.Extend("foo"), e.Binary("FOO")),
      e.Apply(e.Apply(e.Extend("bar"), e.Integer(0)), e.Empty),
    )
  r.eval(e.Apply(e.Select("foo"), source), [], id)
  |> should.equal(r.Value(r.Binary("FOO")))
  r.eval(e.Apply(e.Select("bar"), source), [], id)
  |> should.equal(r.Value(r.Integer(0)))
}

pub fn case_test() {
  let switch =
    e.Apply(
      e.Apply(e.Case("Some"), e.Lambda("x", e.Variable("x"))),
      e.Apply(
        e.Apply(e.Case("None"), e.Lambda("_", e.Binary("else"))),
        e.NoCases,
      ),
    )

  let source = e.Apply(switch, e.Apply(e.Tag("Some"), e.Binary("foo")))
  r.eval(source, [], id)
  |> should.equal(r.Value(r.Binary("foo")))

  let source = e.Apply(switch, e.Apply(e.Tag("None"), e.Empty))
  r.eval(source, [], id)
  |> should.equal(r.Value(r.Binary("else")))
}

pub fn rasing_effect_test() {
  let source =
    e.Let(
      "a",
      e.Apply(e.Perform("Foo"), e.Integer(1)),
      e.Apply(e.Perform("Bar"), e.Variable("a")),
    )
  assert r.Effect("Foo", lifted, k) = r.eval(source, [], id)
  lifted
  |> should.equal(r.Integer(1))
  assert r.Effect("Bar", lifted, k) = k(r.Binary("reply"))
  lifted
  |> should.equal(r.Binary("reply"))
  assert r.Value(term) = k(r.Record([]))
  term
  |> should.equal(r.Record([]))
}

pub fn effect_in_case_test() {
  let switch =
    e.Apply(
      e.Apply(e.Case("Ok"), e.Lambda("x", e.Variable("x"))),
      e.Apply(e.Apply(e.Case("Error"), e.Perform("Raise")), e.NoCases),
    )

  let source = e.Apply(switch, e.Apply(e.Tag("Ok"), e.Binary("foo")))
  r.eval(source, [], id)
  |> should.equal(r.Value(r.Binary("foo")))

  let source = e.Apply(switch, e.Apply(e.Tag("Error"), e.Binary("nope")))
  assert r.Effect("Raise", lifted, k) = r.eval(source, [], id)
  lifted
  |> should.equal(r.Binary("nope"))
}
