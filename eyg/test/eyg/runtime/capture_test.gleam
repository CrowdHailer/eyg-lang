import gleam/map
import gleam/option.{None, Some}
import eygir/expression as e
import eyg/runtime/interpreter as r
import eyg/runtime/capture
import harness/ffi/env
import harness/stdlib
import gleeunit/should

fn round_trip(term) {
  capture.capture(term)
  |> r.eval(env.empty(), None)
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

  let assert r.Value(term) = r.eval(exp, env.empty(), None)
  capture.capture(term)
  |> r.run(env.empty(), r.Record([]), map.new())
  |> should.equal(Ok(r.Binary("hello")))
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

  let assert r.Value(term) = r.eval(exp, env.empty(), None)
  let captured = capture.capture(term)

  let e = env.empty()
  r.eval(
    captured,
    e,
    Some(r.Kont(
      r.CallWith(r.Binary("A"), [], e),
      Some(r.Kont(r.CallWith(r.Binary("B"), [], e), None)),
    )),
  )
  |> should.equal(r.Value(r.LinkedList([r.Binary("A"), r.Binary("B")])))
}

pub fn single_let_capture_test() {
  let exp = e.Let("a", e.Binary("external"), e.Lambda("_", e.Variable("a")))

  let assert r.Value(term) = r.eval(exp, env.empty(), None)
  capture.capture(term)
  |> r.run(env.empty(), r.Record([]), map.new())
  |> should.equal(Ok(r.Binary("external")))
}

// This test makes sure a given env value is captured only once
pub fn duplicate_capture_test() {
  let func = e.Lambda("_", e.Let("_", e.Variable("std"), e.Variable("std")))
  let exp = e.Let("std", e.Binary("Standard"), func)
  let assert r.Value(term) = r.eval(exp, env.empty(), None)
  capture.capture(term)
  |> should.equal(exp)
}

pub fn ordered_capture_test() {
  let exp =
    e.Let(
      "a",
      e.Binary("A"),
      e.Let(
        "b",
        e.Binary("B"),
        e.Lambda("_", e.Let("inner", e.Variable("a"), e.Variable("b"))),
      ),
    )
  let assert r.Value(term) = r.eval(exp, env.empty(), None)
  capture.capture(term)
  |> should.equal(exp)
}

pub fn ordered_fn_capture_test() {
  let exp =
    e.Let(
      "a",
      e.Binary("A"),
      e.Let("b", e.Lambda("_", e.Variable("a")), e.Lambda("_", e.Variable("b"))),
    )
  let assert r.Value(term) = r.eval(exp, env.empty(), None)
  capture.capture(term)
  |> should.equal(exp)
}

pub fn capture_shadowed_variable_test() {
  let exp =
    e.Let(
      "a",
      e.Binary("first"),
      e.Let("a", e.Binary("second"), e.Lambda("_", e.Variable("a"))),
    )

  let assert r.Value(term) = r.eval(exp, env.empty(), None)
  capture.capture(term)
  |> r.run(env.empty(), r.Record([]), map.new())
  |> should.equal(Ok(r.Binary("second")))
}

pub fn only_needed_values_captured_test() {
  let exp =
    e.Let(
      "a",
      e.Binary("ignore"),
      e.Let(
        "b",
        e.Lambda("_", e.Variable("a")),
        e.Let("c", e.Binary("yes"), e.Lambda("_", e.Variable("c"))),
      ),
    )
  let assert r.Value(term) = r.eval(exp, env.empty(), None)
  capture.capture(term)
  |> should.equal(e.Let("c", e.Binary("yes"), e.Lambda("_", e.Variable("c"))))
}

pub fn double_catch_test() {
  let exp =
    e.Let(
      "std",
      e.Binary("Standard"),
      e.Let(
        "f0",
        e.Lambda("_", e.Variable("std")),
        e.Let(
          "f1",
          e.Lambda("_", e.Variable("f0")),
          e.Let(
            "f2",
            e.Lambda("_", e.Variable("std")),
            e.list([e.Variable("f1"), e.Variable("f2")]),
          ),
        ),
      ),
    )
  let assert r.Value(term) = r.eval(exp, env.empty(), None)
  capture.capture(term)
  |> should.equal(e.Let(
    "std",
    e.Binary("Standard"),
    e.Let(
      "f0",
      e.Lambda("_", e.Variable("std")),
      // Always inlineing functions can make output quite large, although much smaller without environment.
      // A possible solution is to always lambda lift if assuming function are large parts of AST
      e.list([e.Lambda("_", e.Variable("f0")), e.Lambda("_", e.Variable("std"))]),
    ),
  ))
}

pub fn fn_in_env_test() {
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
  let assert r.Value(term) = r.eval(exp, env.empty(), None)
  capture.capture(term)
  |> r.run(env.empty(), r.Record([]), map.new())
  |> should.equal(Ok(r.Binary("value")))
}

pub fn tagged_test() {
  let exp = e.Tag("Ok")
  let env = env.empty()
  let assert r.Value(term) = r.eval(exp, env, None)

  let arg = r.Binary("later")
  capture.capture(term)
  |> r.run(env.empty(), arg, map.new())
  |> should.equal(Ok(r.Tagged("Ok", arg)))
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

  let assert r.Value(term) = r.eval(exp, env.empty(), None)
  let next = capture.capture(term)

  let arg = r.Tagged("Ok", r.Record([]))
  next
  |> r.run(env.empty(), arg, map.new())
  |> should.equal(Ok(r.Binary("good")))

  let arg = r.Tagged("Error", r.Record([]))
  next
  |> r.run(env.empty(), arg, map.new())
  |> should.equal(Ok(r.Binary("bad")))
}

pub fn partial_case_test() {
  let exp = e.Apply(e.Case("Ok"), e.Lambda("_", e.Binary("good")))

  let assert r.Value(term) = r.eval(exp, env.empty(), None)
  let rest =
    e.Apply(e.Apply(e.Case("Error"), e.Lambda("_", e.Binary("bad"))), e.NoCases)
  let assert r.Value(rest) = r.eval(rest, env.empty(), None)

  let next = capture.capture(term)

  let arg = r.Tagged("Ok", r.Record([]))
  let e = env.empty()
  r.eval(
    next,
    e,
    Some(r.Kont(
      r.CallWith(rest, [], e),
      Some(r.Kont(r.CallWith(arg, [], e), None)),
    )),
  )
  |> should.equal(r.Value(r.Binary("good")))

  let arg = r.Tagged("Error", r.Record([]))
  r.eval(
    next,
    e,
    Some(r.Kont(
      r.CallWith(rest, [], e),
      Some(r.Kont(r.CallWith(arg, [], e), None)),
    )),
  )
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
  let assert r.Value(term) = r.eval(exp, env.empty(), None)
  let next = capture.capture(term)

  let exec = e.Lambda("_", e.Apply(e.Tag("Ok"), e.Binary("some string")))
  let assert r.Value(exec) = r.eval(exec, env.empty(), None)

  next
  |> r.run(env.empty(), exec, map.new())
  |> should.equal(Ok(r.Tagged("Ok", r.Binary("some string"))))

  let exec = e.Lambda("_", e.Apply(e.Perform("Abort"), e.Binary("failure")))
  let assert r.Value(exec) = r.eval(exec, env.empty(), None)

  next
  |> r.run(env.empty(), exec, map.new())
  |> should.equal(Ok(r.Tagged("Error", r.Binary("failure"))))
}

// pub fn capture_resume_test() {
//   let handler =
//     e.Lambda(
//       "message",
//       // e.Lambda("k", e.Apply(e.Tag("Stopped"), e.Variable("k"))),
//       e.Lambda("k", e.Variable("k")),
//     )

//   let exec =
//     e.Lambda(
//       "_",
//       e.Let(
//         "_",
//         e.Apply(e.Perform("Log"), e.Binary("first")),
//         e.Let("_", e.Apply(e.Perform("Log"), e.Binary("second")), e.Integer(0)),
//       ),
//     )
//   let exp = e.Apply(e.Apply(e.Handle("Log"), handler), exec)
//   let assert r.Value(term) = r.eval(exp, env.empty(), None)
//   let next = capture.capture(term)

//   next
//   |> r.eval(env.empty(), r.eval_call(_, r.Binary("fooo"), [], env.empty(), None))
//   // This should return a effect of subsequent logs, I don't know how to do this
// }

pub fn builtin_arity1_test() {
  let env = stdlib.env()
  let exp = e.Builtin("list_pop")
  let assert r.Value(term) = r.eval(exp, env, None)
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
  |> r.run(env, r.LinkedList([r.Integer(1), r.Integer(2)]), map.new())
  |> should.equal(Ok(split))

  // same as complete eval
  let exp =
    e.Apply(
      exp,
      e.Apply(
        e.Apply(e.Cons, e.Integer(1)),
        e.Apply(e.Apply(e.Cons, e.Integer(2)), e.Tail),
      ),
    )
  r.eval(exp, stdlib.env(), None)
  |> should.equal(r.Value(split))
}

pub fn builtin_arity3_test() {
  let env = stdlib.env()
  let list =
    e.Apply(
      e.Apply(e.Cons, e.Integer(1)),
      e.Apply(e.Apply(e.Cons, e.Integer(2)), e.Tail),
    )
  let exp = e.Apply(e.Apply(e.Builtin("list_fold"), list), e.Integer(0))
  let assert r.Value(term) = r.eval(exp, env, None)
  let next = capture.capture(term)

  next
  |> r.run(env, r.Binary("not a function"), map.new())
  |> should.equal(Error(#(r.NotAFunction(r.Binary("not a function")), [])))

  let reduce_exp = e.Lambda("el", e.Lambda("acc", e.Variable("el")))
  let assert r.Value(reduce) = r.eval(reduce_exp, env, None)
  next
  |> r.run(env, reduce, map.new())
  |> should.equal(Ok(r.Integer(2)))

  // same as complete eval
  let exp = e.Apply(exp, reduce_exp)
  r.eval(exp, env, None)
  |> should.equal(r.Value(r.Integer(2)))
}
