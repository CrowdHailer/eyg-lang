import gleam/io
import eygir/expression as e
import eyg/runtime/interpreter as r
import eyg/runtime/capture
import gleeunit/should

fn round_trip(term) {
  capture.capture(term)
  |> r.eval([], r.Value)
}

fn check_term(term) {
  round_trip(term)
  |> should.equal(r.Value(term))
}

pub fn literal_test() {
  check_term(r.Integer(0))
  check_term(r.Binary("hello"))
  check_term(r.LinkedList([]))
  check_term(r.LinkedList([r.Integer(1), r.Integer(2)]))
  check_term(r.Record([]))
  check_term(r.Record([
    #("foo", r.Binary("hey")),
    #("nested", r.Record([#("bar", r.Binary("inner"))])),
  ]))
  check_term(r.Tagged("Outer", r.Tagged("Inner", r.Integer(0))))
}

pub fn simple_fn_test() {
  let exp = e.Lambda("_", e.Binary("hello"))

  let assert r.Value(term) = r.eval(exp, [], r.Value)
  capture.capture(term)
  |> r.eval([], r.eval_call(_, r.Record([]), r.Value))
  |> should.equal(r.Value(r.Binary("hello")))
}

pub fn nested_fn_test() {
  let exp =
    e.Lambda(
      "a",
      e.Lambda(
        "b",
        e.Apply(
          e.Apply(e.Cons, e.Variable("a")),
          e.Apply(e.Apply(e.Cons, e.Variable("b")), e.Tail),
        ),
      ),
    )

  let assert r.Value(term) = r.eval(exp, [], r.Value)
  capture.capture(term)
  |> r.eval(
    [],
    r.eval_call(_, r.Binary("A"), r.eval_call(_, r.Binary("B"), r.Value)),
  )
  |> should.equal(r.Value(r.LinkedList([r.Binary("A"), r.Binary("B")])))
}

pub fn let_capture_test() {
  let exp = e.Let("a", e.Binary("external"), e.Lambda("_", e.Variable("a")))

  let assert r.Value(term) = r.eval(exp, [], r.Value)
  capture.capture(term)
  |> r.eval([], r.eval_call(_, r.Record([]), r.Value))
  |> should.equal(r.Value(r.Binary("external")))
}

pub fn renamed_test_test() {
  let exp =
    e.Let(
      "a",
      e.Binary("first"),
      e.Let("a", e.Binary("second"), e.Lambda("_", e.Variable("a"))),
    )

  let assert r.Value(term) = r.eval(exp, [], r.Value)
  capture.capture(term)
  |> r.eval([], r.eval_call(_, r.Record([]), r.Value))
  |> should.equal(r.Value(r.Binary("second")))
}

pub fn fn_in_env_test() -> Nil {
  let exp =
    e.Let(
      "a",
      e.Binary("value"),
      e.Let(
        "a",
        e.Lambda("_", e.Variable("a")),
        e.Lambda("_", e.Apply(e.Variable("a"), e.Empty)),
      ),
    )
  let assert r.Value(term) = r.eval(exp, [], r.Value)
  capture.capture(term)
  |> r.eval([], r.eval_call(_, r.Record([]), r.Value))
  |> should.equal(r.Value(r.Binary("value")))
}

pub fn tagged_test() {
  let exp = e.Tag("Ok")

  let arg = r.Binary("later")
  let assert r.Value(term) = r.eval(exp, [], r.Value)
  capture.capture(term)
  |> r.eval([], r.eval_call(_, arg, r.Value))
  |> should.equal(r.Value(r.Tagged("Ok", arg)))
}

pub fn case_test() {
  let exp =
    e.Apply(
      e.Apply(e.Case("Ok"), e.Lambda("_", e.Binary("good"))),
      e.Apply(
        e.Apply(e.Case("Error"), e.Lambda("_", e.Binary("bad"))),
        e.NoCases,
      ),
    )

  let arg = r.Tagged("Ok", r.Record([]))
  let assert r.Value(term) = r.eval(exp, [], r.Value)
  capture.capture(term)
  |> r.eval([], r.eval_call(_, arg, r.Value))
  |> should.equal(r.Value(r.Binary("good")))
}
// TODO test and demo this
// capture logs and send to client
// fn() {
//   log "abc"
//   log "xyz"
//   Done 0
// handle
//   Log value, k -> Cont k
// }
// |> serialize
