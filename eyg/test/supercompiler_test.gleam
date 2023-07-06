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
