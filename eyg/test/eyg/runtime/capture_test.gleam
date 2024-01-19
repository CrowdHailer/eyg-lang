import gleam/dict
import eygir/expression as e
import eyg/runtime/interpreter/runner as r
import eyg/runtime/value as v
import eyg/runtime/break
import eyg/runtime/capture
import harness/ffi/env
import harness/stdlib
import gleeunit/should

fn round_trip(term) {
  capture.capture(term)
  |> r.execute(env.empty(), dict.new())
}

fn check_term(term) {
  round_trip(term)
  |> should.equal(Ok(term))
}

pub fn literal_test() {
  check_term(v.Integer(0))
  check_term(v.Str("hello"))
  check_term(v.LinkedList([]))
  check_term(v.LinkedList([v.Integer(1), v.Integer(2)]))
  check_term(v.unit)
  check_term(
    v.Record([
      #("foo", v.Str("hey")),
      #("nested", v.Record([#("bar", v.Str("inner"))])),
    ]),
  )
  check_term(v.Tagged("Outer", v.Tagged("Inner", v.Integer(0))))
}

pub fn run(source, env, args, extrinsic) {
  case r.execute(source, env, extrinsic) {
    // env not needed in resume but it is in the original execute call, for builtins
    Ok(f) -> r.resume(f, args, env, extrinsic)
    Error(reason) -> Error(reason)
  }
}

pub fn simple_fn_test() {
  let exp = e.Lambda("_", e.Str("hello"))

  let assert Ok(term) = r.execute(exp, env.empty(), dict.new())
  capture.capture(term)
  |> run(env.empty(), [v.unit], dict.new())
  |> should.equal(Ok(v.Str("hello")))
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

  let assert Ok(term) = r.execute(exp, env.empty(), dict.new())
  let captured = capture.capture(term)

  let e = env.empty()
  run(captured, e, [v.Str("A"), v.Str("B")], dict.new())
  |> should.equal(Ok(v.LinkedList([v.Str("A"), v.Str("B")])))
}

pub fn single_let_capture_test() {
  let exp = e.Let("a", e.Str("external"), e.Lambda("_", e.Variable("a")))

  let assert Ok(term) = r.execute(exp, env.empty(), dict.new())
  capture.capture(term)
  |> run(env.empty(), [v.unit], dict.new())
  |> should.equal(Ok(v.Str("external")))
}

// This test makes sure a given env value is captured only once
pub fn duplicate_capture_test() {
  let func = e.Lambda("_", e.Let("_", e.Variable("std"), e.Variable("std")))
  let exp = e.Let("std", e.Str("Standard"), func)
  let assert Ok(term) = r.execute(exp, env.empty(), dict.new())
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
  let assert Ok(term) = r.execute(exp, env.empty(), dict.new())
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
  let assert Ok(term) = r.execute(exp, env.empty(), dict.new())
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

  let assert Ok(term) = r.execute(exp, env.empty(), dict.new())
  capture.capture(term)
  |> run(env.empty(), [v.unit], dict.new())
  |> should.equal(Ok(v.Str("second")))
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
  let assert Ok(term) = r.execute(exp, env.empty(), dict.new())
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
  let assert Ok(term) = r.execute(exp, env.empty(), dict.new())
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
  let assert Ok(term) = r.execute(exp, env.empty(), dict.new())
  capture.capture(term)
  |> run(env.empty(), [v.unit], dict.new())
  |> should.equal(Ok(v.Str("value")))
}

pub fn tagged_test() {
  let exp = e.Tag("Ok")
  let env = env.empty()
  let assert Ok(term) = r.execute(exp, env, dict.new())

  let arg = v.Str("later")
  capture.capture(term)
  |> run(env.empty(), [arg], dict.new())
  |> should.equal(Ok(v.Tagged("Ok", arg)))
}

pub fn case_test() {
  let exp =
    e.Apply(
      e.Apply(e.Case("Ok"), e.Lambda("_", e.Str("good"))),
      e.Apply(e.Apply(e.Case("Error"), e.Lambda("_", e.Str("bad"))), e.NoCases),
    )

  let assert Ok(term) = r.execute(exp, env.empty(), dict.new())
  let next = capture.capture(term)

  let arg = v.Tagged("Ok", v.unit)
  next
  |> run(env.empty(), [arg], dict.new())
  |> should.equal(Ok(v.Str("good")))

  let arg = v.Tagged("Error", v.unit)
  next
  |> run(env.empty(), [arg], dict.new())
  |> should.equal(Ok(v.Str("bad")))
}

pub fn partial_case_test() {
  let exp = e.Apply(e.Case("Ok"), e.Lambda("_", e.Str("good")))

  let assert Ok(term) = r.execute(exp, env.empty(), dict.new())
  let rest =
    e.Apply(e.Apply(e.Case("Error"), e.Lambda("_", e.Str("bad"))), e.NoCases)
  let assert Ok(rest) = r.execute(rest, env.empty(), dict.new())

  let next = capture.capture(term)

  let arg = v.Tagged("Ok", v.unit)
  let e = env.empty()
  run(next, e, [rest, arg], dict.new())
  |> should.equal(Ok(v.Str("good")))

  let arg = v.Tagged("Error", v.unit)
  run(next, e, [rest, arg], dict.new())
  |> should.equal(Ok(v.Str("bad")))
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
  let assert Ok(term) = r.execute(exp, env.empty(), dict.new())
  let next = capture.capture(term)

  let exec = e.Lambda("_", e.Apply(e.Tag("Ok"), e.Str("some string")))
  let assert Ok(exec) = r.execute(exec, env.empty(), dict.new())

  next
  |> run(env.empty(), [exec], dict.new())
  |> should.equal(Ok(v.Tagged("Ok", v.Str("some string"))))

  let exec = e.Lambda("_", e.Apply(e.Perform("Abort"), e.Str("failure")))
  let assert Ok(exec) = r.execute(exec, env.empty(), dict.new())

  next
  |> run(env.empty(), [exec], dict.new())
  |> should.equal(Ok(v.Tagged("Error", v.Str("failure"))))
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
//   let assert Ok(term) = r.execute(exp, env.empty(), dict.new())
//   let next = capture.capture(term)

//   next
//   |> r.execute(env.empty(), r.eval_call(_, v.Str("fooo"), [], env.empty(), dict.new()))
//   // This should return a effect of subsequent logs, I don't know how to do this
// }

pub fn builtin_arity1_test() {
  let env = stdlib.env()
  let exp = e.Builtin("list_pop")
  let assert Ok(term) = r.execute(exp, env, dict.new())
  let next = capture.capture(term)

  let split =
    v.Tagged(
      "Ok",
      v.Record([
        #("head", v.Integer(1)),
        #("tail", v.LinkedList([v.Integer(2)])),
      ]),
    )
  next
  |> run(env, [v.LinkedList([v.Integer(1), v.Integer(2)])], dict.new())
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
  r.execute(exp, stdlib.env(), dict.new())
  |> should.equal(Ok(split))
}

pub fn builtin_arity3_test() {
  let env = stdlib.env()
  let list =
    e.Apply(
      e.Apply(e.Cons, e.Integer(1)),
      e.Apply(e.Apply(e.Cons, e.Integer(2)), e.Tail),
    )
  let exp = e.Apply(e.Apply(e.Builtin("list_fold"), list), e.Integer(0))
  let assert Ok(term) = r.execute(exp, env, dict.new())
  let next = capture.capture(term)

  let ret = run(next, env, [v.Str("not a function")], dict.new())
  let assert Error(#(break.NotAFunction(v.Str("not a function")), [], _, _)) =
    ret

  let reduce_exp = e.Lambda("el", e.Lambda("acc", e.Variable("el")))
  let assert Ok(reduce) = r.execute(reduce_exp, env, dict.new())
  next
  |> run(env, [reduce], dict.new())
  |> should.equal(Ok(v.Integer(2)))

  // same as complete eval
  let exp = e.Apply(exp, reduce_exp)
  r.execute(exp, env, dict.new())
  |> should.equal(Ok(v.Integer(2)))
}
