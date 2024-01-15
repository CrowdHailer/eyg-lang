import gleam/dict
import gleam/option.{None, Some}
import eygir/expression as e
import eyg/runtime/interpreter as r
import eyg/runtime/capture
import harness/ffi/env
import harness/stdlib
import gleeunit/should

fn round_trip(term) {
  capture.capture(term)
  |> r.eval(env.empty(), r.WillRenameAsDone(dict.new()))
}

fn check_term(term) {
  round_trip(term)
  |> should.equal(r.Value(term))
}

pub fn literal_test() {
  check_term(r.Integer(0))
  check_term(r.Str("hello"))
  check_term(r.LinkedList([]))
  check_term(r.LinkedList([r.Integer(1), r.Integer(2)]))
  check_term(r.Record([]))
  check_term(
    r.Record([
      #("foo", r.Str("hey")),
      #("nested", r.Record([#("bar", r.Str("inner"))])),
    ]),
  )
  check_term(r.Tagged("Outer", r.Tagged("Inner", r.Integer(0))))
}

pub fn simple_fn_test() {
  let exp = e.Lambda("_", e.Str("hello"))

  let assert r.Value(term) =
    r.eval(exp, env.empty(), r.WillRenameAsDone(dict.new()))
  capture.capture(term)
  |> r.run(env.empty(), r.Record([]), dict.new())
  |> should.equal(Ok(r.Str("hello")))
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

  let assert r.Value(term) =
    r.eval(exp, env.empty(), r.WillRenameAsDone(dict.new()))
  let captured = capture.capture(term)

  let e = env.empty()
  r.eval(
    captured,
    e,
    r.Stack(
      r.CallWith(r.Str("A"), [], e),
      r.Stack(r.CallWith(r.Str("B"), [], e), r.WillRenameAsDone(dict.new())),
    ),
  )
  |> should.equal(r.Value(r.LinkedList([r.Str("A"), r.Str("B")])))
}

pub fn single_let_capture_test() {
  let exp = e.Let("a", e.Str("external"), e.Lambda("_", e.Variable("a")))

  let assert r.Value(term) =
    r.eval(exp, env.empty(), r.WillRenameAsDone(dict.new()))
  capture.capture(term)
  |> r.run(env.empty(), r.Record([]), dict.new())
  |> should.equal(Ok(r.Str("external")))
}

// This test makes sure a given env value is captured only once
pub fn duplicate_capture_test() {
  let func = e.Lambda("_", e.Let("_", e.Variable("std"), e.Variable("std")))
  let exp = e.Let("std", e.Str("Standard"), func)
  let assert r.Value(term) =
    r.eval(exp, env.empty(), r.WillRenameAsDone(dict.new()))
  capture.capture(term)
  |> should.equal(exp)
}

pub fn ordered_capture_test() {
  let exp =
    e.Let(
      "a",
      e.Str("A"),
      e.Let(
        "b",
        e.Str("B"),
        e.Lambda("_", e.Let("inner", e.Variable("a"), e.Variable("b"))),
      ),
    )
  let assert r.Value(term) =
    r.eval(exp, env.empty(), r.WillRenameAsDone(dict.new()))
  capture.capture(term)
  |> should.equal(exp)
}

pub fn ordered_fn_capture_test() {
  let exp =
    e.Let(
      "a",
      e.Str("A"),
      e.Let("b", e.Lambda("_", e.Variable("a")), e.Lambda("_", e.Variable("b"))),
    )
  let assert r.Value(term) =
    r.eval(exp, env.empty(), r.WillRenameAsDone(dict.new()))
  capture.capture(term)
  |> should.equal(exp)
}

pub fn capture_shadowed_variable_test() {
  let exp =
    e.Let(
      "a",
      e.Str("first"),
      e.Let("a", e.Str("second"), e.Lambda("_", e.Variable("a"))),
    )

  let assert r.Value(term) =
    r.eval(exp, env.empty(), r.WillRenameAsDone(dict.new()))
  capture.capture(term)
  |> r.run(env.empty(), r.Record([]), dict.new())
  |> should.equal(Ok(r.Str("second")))
}

pub fn only_needed_values_captured_test() {
  let exp =
    e.Let(
      "a",
      e.Str("ignore"),
      e.Let(
        "b",
        e.Lambda("_", e.Variable("a")),
        e.Let("c", e.Str("yes"), e.Lambda("_", e.Variable("c"))),
      ),
    )
  let assert r.Value(term) =
    r.eval(exp, env.empty(), r.WillRenameAsDone(dict.new()))
  capture.capture(term)
  |> should.equal(e.Let("c", e.Str("yes"), e.Lambda("_", e.Variable("c"))))
}

pub fn double_catch_test() {
  let exp =
    e.Let(
      "std",
      e.Str("Standard"),
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
  let assert r.Value(term) =
    r.eval(exp, env.empty(), r.WillRenameAsDone(dict.new()))
  capture.capture(term)
  |> should.equal(e.Let(
    "std",
    e.Str("Standard"),
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
      e.Str("value"),
      e.Let(
        "a",
        e.Lambda("_", e.Variable("a")),
        e.Lambda("_", e.Apply(e.Variable("a"), e.Empty)),
      ),
    )
  let assert r.Value(term) =
    r.eval(exp, env.empty(), r.WillRenameAsDone(dict.new()))
  capture.capture(term)
  |> r.run(env.empty(), r.Record([]), dict.new())
  |> should.equal(Ok(r.Str("value")))
}

pub fn tagged_test() {
  let exp = e.Tag("Ok")
  let env = env.empty()
  let assert r.Value(term) = r.eval(exp, env, r.WillRenameAsDone(dict.new()))

  let arg = r.Str("later")
  capture.capture(term)
  |> r.run(env.empty(), arg, dict.new())
  |> should.equal(Ok(r.Tagged("Ok", arg)))
}

pub fn case_test() {
  let exp =
    e.Apply(
      e.Apply(e.Case("Ok"), e.Lambda("_", e.Str("good"))),
      e.Apply(e.Apply(e.Case("Error"), e.Lambda("_", e.Str("bad"))), e.NoCases),
    )

  let assert r.Value(term) =
    r.eval(exp, env.empty(), r.WillRenameAsDone(dict.new()))
  let next = capture.capture(term)

  let arg = r.Tagged("Ok", r.Record([]))
  next
  |> r.run(env.empty(), arg, dict.new())
  |> should.equal(Ok(r.Str("good")))

  let arg = r.Tagged("Error", r.Record([]))
  next
  |> r.run(env.empty(), arg, dict.new())
  |> should.equal(Ok(r.Str("bad")))
}

pub fn partial_case_test() {
  let exp = e.Apply(e.Case("Ok"), e.Lambda("_", e.Str("good")))

  let assert r.Value(term) =
    r.eval(exp, env.empty(), r.WillRenameAsDone(dict.new()))
  let rest =
    e.Apply(e.Apply(e.Case("Error"), e.Lambda("_", e.Str("bad"))), e.NoCases)
  let assert r.Value(rest) =
    r.eval(rest, env.empty(), r.WillRenameAsDone(dict.new()))

  let next = capture.capture(term)

  let arg = r.Tagged("Ok", r.Record([]))
  let e = env.empty()
  r.eval(
    next,
    e,
    r.Stack(
      r.CallWith(rest, [], e),
      r.Stack(r.CallWith(arg, [], e), r.WillRenameAsDone(dict.new())),
    ),
  )
  |> should.equal(r.Value(r.Str("good")))

  let arg = r.Tagged("Error", r.Record([]))
  r.eval(
    next,
    e,
    r.Stack(
      r.CallWith(rest, [], e),
      r.Stack(r.CallWith(arg, [], e), r.WillRenameAsDone(dict.new())),
    ),
  )
  |> should.equal(r.Value(r.Str("bad")))
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
  let assert r.Value(term) =
    r.eval(exp, env.empty(), r.WillRenameAsDone(dict.new()))
  let next = capture.capture(term)

  let exec = e.Lambda("_", e.Apply(e.Tag("Ok"), e.Str("some string")))
  let assert r.Value(exec) =
    r.eval(exec, env.empty(), r.WillRenameAsDone(dict.new()))

  next
  |> r.run(env.empty(), exec, dict.new())
  |> should.equal(Ok(r.Tagged("Ok", r.Str("some string"))))

  let exec = e.Lambda("_", e.Apply(e.Perform("Abort"), e.Str("failure")))
  let assert r.Value(exec) =
    r.eval(exec, env.empty(), r.WillRenameAsDone(dict.new()))

  next
  |> r.run(env.empty(), exec, dict.new())
  |> should.equal(Ok(r.Tagged("Error", r.Str("failure"))))
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
//         e.Apply(e.Perform("Log"), e.Str("first")),
//         e.Let("_", e.Apply(e.Perform("Log"), e.Str("second")), e.Integer(0)),
//       ),
//     )
//   let exp = e.Apply(e.Apply(e.Handle("Log"), handler), exec)
//   let assert r.Value(term) = r.eval(exp, env.empty(), r.WillRenameAsDone(dict.new()))
//   let next = capture.capture(term)

//   next
//   |> r.eval(env.empty(), r.eval_call(_, r.Str("fooo"), [], env.empty(), r.WillRenameAsDone(dict.new())))
//   // This should return a effect of subsequent logs, I don't know how to do this
// }

pub fn builtin_arity1_test() {
  let env = stdlib.env()
  let exp = e.Builtin("list_pop")
  let assert r.Value(term) = r.eval(exp, env, r.WillRenameAsDone(dict.new()))
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
  |> r.run(env, r.LinkedList([r.Integer(1), r.Integer(2)]), dict.new())
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
  r.eval(exp, stdlib.env(), r.WillRenameAsDone(dict.new()))
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
  let assert r.Value(term) = r.eval(exp, env, r.WillRenameAsDone(dict.new()))
  let next = capture.capture(term)

  next
  |> r.run(env, r.Str("not a function"), dict.new())
  |> should.equal(Error(#(r.NotAFunction(r.Str("not a function")), [])))

  let reduce_exp = e.Lambda("el", e.Lambda("acc", e.Variable("el")))
  let assert r.Value(reduce) =
    r.eval(reduce_exp, env, r.WillRenameAsDone(dict.new()))
  next
  |> r.run(env, reduce, dict.new())
  |> should.equal(Ok(r.Integer(2)))

  // same as complete eval
  let exp = e.Apply(exp, reduce_exp)
  r.eval(exp, env, r.WillRenameAsDone(dict.new()))
  |> should.equal(r.Value(r.Integer(2)))
}
