import eyg/runtime/break
import eyg/runtime/capture
import eyg/runtime/interpreter/runner as r
import eyg/runtime/value as v
import eygir/annotated as a
import gleam/dict
import gleam/list
import gleeunit/should
import harness/ffi/env
import harness/stdlib

fn round_trip(term) {
  capture.capture(term, Nil)
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

fn run(source, env, args, extrinsic) {
  let args = list.map(args, fn(v) { #(v, Nil) })
  case r.execute(source, env, extrinsic) {
    // env not needed in resume but it is in the original execute call, for builtins
    Ok(f) -> r.call(f, args, env, extrinsic)
    Error(reason) -> Error(reason)
  }
}

pub fn simple_fn_test() {
  let exp = a.lambda("_", a.string("hello"))

  let assert Ok(term) = run(exp, env.empty(), [], dict.new())
  capture.capture(term, Nil)
  |> run(env.empty(), [v.unit], dict.new())
  |> should.equal(Ok(v.Str("hello")))
}

pub fn nested_fn_test() {
  let exp =
    a.lambda(
      "a",
      a.lambda(
        "b",
        a.apply(
          a.apply(a.cons(), a.variable("a")),
          a.apply(a.apply(a.cons(), a.variable("b")), a.tail()),
        ),
      ),
    )

  let assert Ok(term) = run(exp, env.empty(), [], dict.new())
  let captured = capture.capture(term, Nil)

  let e = env.empty()
  run(captured, e, [v.Str("A"), v.Str("B")], dict.new())
  |> should.equal(Ok(v.LinkedList([v.Str("A"), v.Str("B")])))
}

pub fn single_let_capture_test() {
  let exp = a.let_("a", a.string("external"), a.lambda("_", a.variable("a")))

  let assert Ok(term) = run(exp, env.empty(), [], dict.new())
  capture.capture(term, Nil)
  |> run(env.empty(), [v.unit], dict.new())
  |> should.equal(Ok(v.Str("external")))
}

// This test makes sure a given env value is captured only once
pub fn duplicate_capture_test() {
  let func = a.lambda("_", a.let_("_", a.variable("std"), a.variable("std")))
  let exp = a.let_("std", a.string("Standard"), func)

  let assert Ok(term) = run(exp, env.empty(), [], dict.new())
  capture.capture(term, Nil)
  |> should.equal(exp)
}

pub fn ordered_capture_test() {
  let exp =
    a.let_(
      "a",
      a.string("A"),
      a.let_(
        "b",
        a.string("B"),
        a.lambda("_", a.let_("inner", a.variable("a"), a.variable("b"))),
      ),
    )

  let assert Ok(term) = run(exp, env.empty(), [], dict.new())
  capture.capture(term, Nil)
  |> should.equal(exp)
}

pub fn ordered_fn_capture_test() {
  let exp =
    a.let_(
      "a",
      a.string("A"),
      a.let_(
        "b",
        a.lambda("_", a.variable("a")),
        a.lambda("_", a.variable("b")),
      ),
    )

  let assert Ok(term) = run(exp, env.empty(), [], dict.new())
  capture.capture(term, Nil)
  |> should.equal(exp)
}

pub fn capture_shadowed_variable_test() {
  let exp =
    a.let_(
      "a",
      a.string("first"),
      a.let_("a", a.string("second"), a.lambda("_", a.variable("a"))),
    )

  let assert Ok(term) = run(exp, env.empty(), [], dict.new())
  capture.capture(term, Nil)
  |> run(env.empty(), [v.unit], dict.new())
  |> should.equal(Ok(v.Str("second")))
}

pub fn only_needed_values_captured_test() {
  let exp =
    a.let_(
      "a",
      a.string("ignore"),
      a.let_(
        "b",
        a.lambda("_", a.variable("a")),
        a.let_("c", a.string("yes"), a.lambda("_", a.variable("c"))),
      ),
    )

  let assert Ok(term) = run(exp, env.empty(), [], dict.new())
  capture.capture(term, Nil)
  |> should.equal(a.let_("c", a.string("yes"), a.lambda("_", a.variable("c"))))
}

pub fn double_catch_test() {
  let exp =
    a.let_(
      "std",
      a.string("Standard"),
      a.let_(
        "f0",
        a.lambda("_", a.variable("std")),
        a.let_(
          "f1",
          a.lambda("_", a.variable("f0")),
          a.let_(
            "f2",
            a.lambda("_", a.variable("std")),
            a.list([a.variable("f1"), a.variable("f2")]),
          ),
        ),
      ),
    )

  let assert Ok(term) = run(exp, env.empty(), [], dict.new())
  capture.capture(term, Nil)
  |> should.equal(a.let_(
    "std",
    a.string("Standard"),
    a.let_(
      "f0",
      a.lambda("_", a.variable("std")),
      // Always inlineing functions can make output quite large, although much smaller without environment.
      // A possible solution is to always lambda lift if assuming function are large parts of AST
      a.list([a.lambda("_", a.variable("f0")), a.lambda("_", a.variable("std"))]),
    ),
  ))
}

pub fn fn_in_env_test() {
  let exp =
    a.let_(
      "a",
      a.string("value"),
      a.let_(
        "a",
        a.lambda("_", a.variable("a")),
        a.lambda("_", a.apply(a.variable("a"), a.empty())),
      ),
    )

  let assert Ok(term) = run(exp, env.empty(), [], dict.new())
  capture.capture(term, Nil)
  |> run(env.empty(), [v.unit], dict.new())
  |> should.equal(Ok(v.Str("value")))
}

pub fn tagged_test() {
  let exp = a.tag("Ok")
  let env = env.empty()
  let assert Ok(term) = run(exp, env, [], dict.new())

  let arg = v.Str("later")
  capture.capture(term, Nil)
  |> run(env.empty(), [arg], dict.new())
  |> should.equal(Ok(v.Tagged("Ok", arg)))
}

pub fn case_test() {
  let exp =
    a.apply(
      a.apply(a.case_("Ok"), a.lambda("_", a.string("good"))),
      a.apply(
        a.apply(a.case_("Error"), a.lambda("_", a.string("bad"))),
        a.nocases(),
      ),
    )

  let assert Ok(term) = run(exp, env.empty(), [], dict.new())
  let next = capture.capture(term, Nil)

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
  let exp = a.apply(a.case_("Ok"), a.lambda("_", a.string("good")))

  let assert Ok(term) = run(exp, env.empty(), [], dict.new())
  let rest =
    a.apply(
      a.apply(a.case_("Error"), a.lambda("_", a.string("bad"))),
      a.nocases(),
    )

  let assert Ok(rest) = run(rest, env.empty(), [], dict.new())

  let next = capture.capture(term, Nil)

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
    a.apply(
      a.handle("Abort"),
      a.lambda(
        "value",
        a.lambda("_k", a.apply(a.tag("Error"), a.variable("value"))),
      ),
    )

  let assert Ok(term) = run(exp, env.empty(), [], dict.new())
  let next = capture.capture(term, Nil)

  let exec = a.lambda("_", a.apply(a.tag("Ok"), a.string("some string")))

  let assert Ok(exec) = run(exec, env.empty(), [], dict.new())

  next
  |> run(env.empty(), [exec], dict.new())
  |> should.equal(Ok(v.Tagged("Ok", v.Str("some string"))))

  let exec = a.lambda("_", a.apply(a.perform("Abort"), a.string("failure")))

  let assert Ok(exec) = run(exec, env.empty(), [], dict.new())

  next
  |> run(env.empty(), [exec], dict.new())
  |> should.equal(Ok(v.Tagged("Error", v.Str("failure"))))
}

// pub fn capture_resume_test() {
//   let handler =
//     a.lambda(
//       "message",
//       // a.lambda("k", a.apply(a.tag("Stopped"), a.variable("k"))),
//       a.lambda("k", a.variable("k")),
//     )

//   let exec =
//     a.lambda(
//       "_",
//       a.let_(
//         "_",
//         a.apply(a.perform("Log"), a.string("first")),
//         a.let_("_", a.apply(a.perform("Log"), a.string("second")), a.integer(0)),
//       ),
//     )
//   let exp = a.apply(a.apply(a.handle("Log"), handler), exec)
//   let assert Ok(term) = r.execute(exp, env.empty(), dict.new())
//   let next = capture.capture(term,Nil)

//   next
//   |> r.execute(env.empty(), r.eval_call(_, v.Str("fooo"), [], env.empty(), dict.new()))
//   // This should return a effect of subsequent logs, I don't know how to do this
// }

pub fn builtin_arity1_test() {
  let env = stdlib.env()
  let exp = a.builtin("list_pop")
  let assert Ok(term) = run(exp, env, [], dict.new())
  let next = capture.capture(term, Nil)

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
    a.apply(
      exp,
      a.apply(
        a.apply(a.cons(), a.integer(1)),
        a.apply(a.apply(a.cons(), a.integer(2)), a.tail()),
      ),
    )

  run(exp, stdlib.env(), [], dict.new())
  |> should.equal(Ok(split))
}

pub fn builtin_arity3_test() {
  let env = stdlib.env()
  let list =
    a.apply(
      a.apply(a.cons(), a.integer(1)),
      a.apply(a.apply(a.cons(), a.integer(2)), a.tail()),
    )
  let exp = a.apply(a.apply(a.builtin("list_fold"), list), a.integer(0))

  let assert Ok(term) = run(exp, env, [], dict.new())
  let next = capture.capture(term, Nil)

  let ret = run(next, env, [v.Str("not a function")], dict.new())
  let assert Error(#(break.NotAFunction(v.Str("not a function")), Nil, _, _)) =
    ret

  let reduce_exp = a.lambda("el", a.lambda("acc", a.variable("el")))
  let assert Ok(reduce) = run(reduce_exp, env, [], dict.new())
  next
  |> run(env, [reduce], dict.new())
  |> should.equal(Ok(v.Integer(2)))

  // same as complete eval
  let exp = a.apply(exp, reduce_exp)

  run(exp, env, [], dict.new())
  |> should.equal(Ok(v.Integer(2)))
}
