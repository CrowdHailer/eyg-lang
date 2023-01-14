import gleam/json
import gleeunit/should
import eygir/expression as e
import eygir/encode.{to_json}
import eygir/decode.{from_json}

fn round_trip(exp) {
  exp
  |> to_json
  |> json.decode(decode.decoder)
}

fn check_encoding(exp) {
  round_trip(exp)
  |> should.equal(Ok(exp))
}

pub fn expression_test() {
  check_encoding(e.Variable("Foo"))
  check_encoding(e.Lambda("x", e.Variable("x")))
  check_encoding(e.Apply(e.Lambda("x", e.Variable("x")), e.Binary("foo")))
  check_encoding(e.Let("x", e.Binary("hi"), e.Variable("x")))
  check_encoding(e.Integer(5))
  check_encoding(e.Binary("hello"))
  check_encoding(e.Tail)
  check_encoding(e.Cons)
  check_encoding(e.Vacant)
  check_encoding(e.Empty)
  check_encoding(e.Extend("foo"))
  check_encoding(e.Select("foo"))
  check_encoding(e.Tag("foo"))
  check_encoding(e.Case("foo"))
  check_encoding(e.NoCases)
  check_encoding(e.Perform("foo"))
  check_encoding(e.Handle("handle"))
}
