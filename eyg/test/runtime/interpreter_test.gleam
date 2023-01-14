import gleam/io
import gleam/map
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
  let f = fn(x, k) {
    assert r.Binary(value) = x
    r.continue(k, r.Binary(string.reverse(value)))
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

pub fn effect_in_builtin_test() {
  let source =
    e.Apply(
      e.Variable("native_call"),
      e.Lambda(
        "x",
        e.Let(
          "reply",
          e.Apply(e.Perform("Foo"), e.Variable("x")),
          e.Apply(e.Apply(e.Extend("field"), e.Variable("reply")), e.Empty),
        ),
      ),
    )
  let env = [
    #(
      "native_call",
      r.Builtin(fn(x, k) { r.eval_call(x, r.Binary("called"), k) }),
    ),
  ]
  assert r.Effect("Foo", lifted, k) = r.eval(source, env, id)
  lifted
  |> should.equal(r.Binary("called"))
  k(r.Binary("reply"))
  |> should.equal(r.Value(r.Record([#("field", r.Binary("reply"))])))
}

pub fn handler_no_effect_test() {
  let handler =
    e.Lambda("x", e.Lambda("k", e.Apply(e.Tag("Error"), e.Variable("x"))))
  let exec = e.Apply(e.Tag("Ok"), e.Binary("mystring"))
  let source = e.Apply(e.Apply(e.Handle("Throw"), handler), exec)

  r.eval(source, [], id)
  |> should.equal(r.Value(r.Tagged("Ok", r.Binary("mystring"))))
}

pub fn handle_early_return_effect_test() {
  let handler =
    e.Lambda("x", e.Lambda("k", e.Apply(e.Tag("Error"), e.Variable("x"))))
  let exec = e.Apply(e.Perform("Throw"), e.Binary("Bad thing"))
  let source = e.Apply(e.Apply(e.Handle("Throw"), handler), exec)

  r.eval(source, [], id)
  |> should.equal(r.Value(r.Tagged("Error", r.Binary("Bad thing"))))
}

pub fn handle_resume_test() {
  let handler =
    e.Lambda(
      "x",
      e.Lambda(
        "k",
        e.Apply(
          e.Apply(e.Extend("value"), e.Apply(e.Variable("k"), e.Empty)),
          e.Apply(e.Apply(e.Extend("log"), e.Variable("x")), e.Empty),
        ),
      ),
    )

  let exec =
    e.Let(
      "_",
      e.Apply(e.Perform("Log"), e.Binary("my message")),
      e.Integer(100),
    )
  let source = e.Apply(e.Apply(e.Handle("Log"), handler), exec)

  r.eval(source, [], id)
  |> should.equal(r.Value(r.Record([
    #("value", r.Integer(100)),
    #("log", r.Binary("my message")),
  ])))
}

pub fn ignore_other_effect_test() {
  let handler =
    e.Lambda("x", e.Lambda("k", e.Apply(e.Tag("Error"), e.Variable("x"))))
  let exec =
    e.Apply(
      e.Apply(e.Extend("foo"), e.Apply(e.Perform("Foo"), e.Empty)),
      e.Empty,
    )
  let source = e.Apply(e.Apply(e.Handle("Throw"), handler), exec)

  assert r.Effect("Foo", lifted, k) = r.eval(source, [], id)
  lifted
  |> should.equal(r.Record([]))
  // calling k should fall throu
  // Should test wrapping binary here to check K works properly
  k(r.Binary("reply"))
  |> should.equal(r.Value(r.Record([#("foo", r.Binary("reply"))])))
}
// TODO multiple effects
// TODO multiple resumptions
// TODO match with inference
// TODO handle logs in front end code
