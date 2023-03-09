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

  let assert r.Value(term) = r.eval(exp, [], r.Value)
  let next = capture.capture(term)

  let arg = r.Tagged("Ok", r.Record([]))
  next
  |> r.eval([], r.eval_call(_, arg, r.Value))
  |> should.equal(r.Value(r.Binary("good")))

  let arg = r.Tagged("Error", r.Record([]))
  next
  |> r.eval([], r.eval_call(_, arg, r.Value))
  |> should.equal(r.Value(r.Binary("bad")))
}

pub fn partial_case_test() {
  let exp = e.Apply(e.Case("Ok"), e.Lambda("_", e.Binary("good")))

  let assert r.Value(term) = r.eval(exp, [], r.Value)
  let rest =
    e.Apply(e.Apply(e.Case("Error"), e.Lambda("_", e.Binary("bad"))), e.NoCases)
  let assert r.Value(rest) = r.eval(rest, [], r.Value)

  let next = capture.capture(term)

  let arg = r.Tagged("Ok", r.Record([]))
  next
  |> r.eval([], r.eval_call(_, rest, r.eval_call(_, arg, r.Value)))
  |> should.equal(r.Value(r.Binary("good")))

  let arg = r.Tagged("Error", r.Record([]))
  next
  |> r.eval([], r.eval_call(_, rest, r.eval_call(_, arg, r.Value)))
  |> should.equal(r.Value(r.Binary("bad")))
}

pub fn handler_test() {
  let exp =
    e.Apply(
      e.Handle("Abort"),
      e.Lambda(
        "value",
        e.Lambda("_k", e.Apply(e.Tag("Error"), e.Variable("value"))),
      ),
    )
  let assert r.Value(term) = r.eval(exp, [], r.Value)
  let next = capture.capture(term)

  let exec = e.Lambda("_", e.Apply(e.Tag("Ok"), e.Binary("some string")))
  let assert r.Value(exec) = r.eval(exec, [], r.Value)

  next
  |> r.eval([], r.eval_call(_, exec, r.Value))
  |> should.equal(r.Value(r.Tagged("Ok", r.Binary("some string"))))

  let exec = e.Lambda("_", e.Apply(e.Perform("Abort"), e.Binary("failure")))
  let assert r.Value(exec) = r.eval(exec, [], r.Value)

  next
  |> r.eval([], r.eval_call(_, exec, r.Value))
  |> should.equal(r.Value(r.Tagged("Error", r.Binary("failure"))))
}

pub fn capture_resume_test() {
  let handler =
    e.Lambda(
      "message",
      // e.Lambda("k", e.Apply(e.Tag("Stopped"), e.Variable("k"))),
      e.Lambda("k", e.Variable("k")),
    )

  let exec =
    e.Lambda(
      "_",
      e.Let(
        "_",
        e.Apply(e.Perform("Log"), e.Binary("first")),
        e.Let("_", e.Apply(e.Perform("Log"), e.Binary("second")), e.Integer(0)),
      ),
    )
  let exp = e.Apply(e.Apply(e.Handle("Log"), handler), exec)
  let assert r.Value(term) = r.eval(exp, [], r.Value)
  let next = capture.capture(term)

  next
  |> r.eval([], r.eval_call(_, r.Binary("fooo"), r.Value))
  // This should return a effect of subsequent logs, I don't know how to do this
  todo
}

pub fn builtin_arity1_test() {
  let exp = e.Builtin("list_pop")
  let assert r.Value(term) = r.eval(exp, [], r.Value)
  let next = capture.capture(term)

  let split =
    r.Tagged(
      "Ok",
      r.Record([
        #("head", r.Integer(1)),
        #("tail", r.LinkedList([r.Integer(2)])),
      ]),
    )
  next
  |> r.eval(
    [],
    r.eval_call(_, r.LinkedList([r.Integer(1), r.Integer(2)]), r.Value),
  )
  |> should.equal(r.Value(split))

  // same as complete eval
  let exp =
    e.Apply(
      exp,
      e.Apply(
        e.Apply(e.Cons, e.Integer(1)),
        e.Apply(e.Apply(e.Cons, e.Integer(2)), e.Tail),
      ),
    )
  r.eval(exp, [], r.Value)
  |> should.equal(r.Value(split))
}

pub fn builtin_arity3_test() {
  let exp = e.Apply(e.Apply(e.Builtin("list_fold"), e.Tail), e.Integer(0))
  let assert r.Value(term) = r.eval(exp, [], r.Value)
  let next = capture.capture(term)

  let split =
    r.Tagged(
      "Ok",
      r.Record([
        #("head", r.Integer(1)),
        #("tail", r.LinkedList([r.Integer(2)])),
      ]),
    )
  next
  |> r.eval(
    [],
    r.eval_call(_, r.LinkedList([r.Integer(1), r.Integer(2)]), r.Value),
  )
  |> should.equal(r.Value(split))

  // same as complete eval
  let exp =
    e.Apply(
      exp,
      e.Apply(
        e.Apply(e.Cons, e.Integer(1)),
        e.Apply(e.Apply(e.Cons, e.Integer(2)), e.Tail),
      ),
    )
  r.eval(exp, [], r.Value)
  |> should.equal(r.Value(split))
}
