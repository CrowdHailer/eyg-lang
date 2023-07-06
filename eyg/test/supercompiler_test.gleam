import gleam/io
import eygir/expression as e
import eyg/supercompiler.{eval}
import gleeunit/should

pub fn supercompiler_test() {
  eval(e.Let("x", e.Binary("hello"), e.Variable("x")))
  |> should.equal(e.Binary("hello"))

  eval(e.Apply(e.Lambda("_", e.Binary("hello")), e.Binary("ignore")))
  |> should.equal(e.Binary("hello"))

  eval(e.Apply(e.Lambda("x", e.Variable("x")), e.Binary("hello")))
  |> should.equal(e.Binary("hello"))

  eval(e.Apply(e.Builtin("string_uppercase"), e.Binary("hello")))
  |> should.equal(e.Binary("HELLO"))
}

pub fn reduce_body_test() {
  eval(e.Let(
    "x",
    e.Integer(-1),
    e.Lambda("_", e.Apply(e.Builtin("integer_absolute"), e.Variable("x"))),
  ))
  |> should.equal(e.Lambda("_", e.Integer(1)))
}

pub fn shadowing_in_function_test() {
  eval(e.Let("x", e.Integer(5), e.Lambda("x", e.Variable("x"))))
  |> should.equal(e.Lambda("x", e.Variable("x")))
}

pub fn collapse_part_in_apply_test() {
  eval(e.Lambda(
    "x",
    e.Apply(
      e.Apply(e.Builtin("integer_add"), e.Variable("x")),
      e.Apply(e.Apply(e.Builtin("integer_add"), e.Integer(2)), e.Integer(3)),
    ),
  ))
  |> should.equal(e.Lambda(
    "x",
    e.Apply(e.Apply(e.Builtin("integer_add"), e.Variable("x")), e.Integer(5)),
  ))
}

pub fn variable_shadowing_test() {
  eval(e.Lambda(
    "y",
    e.Let("x", e.Integer(5), e.Let("x", e.Variable("y"), e.Variable("x"))),
  ))
  |> should.equal(e.Lambda("x", e.Variable("x")))
}


// in language helper for list
// lang_eval
// check that error is in the right place