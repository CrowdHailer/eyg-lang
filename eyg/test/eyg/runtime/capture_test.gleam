import eyg/ir/tree as ir
import eyg/runtime/break
import eyg/runtime/capture
import eyg/runtime/interpreter/runner as r
import eyg/runtime/value as v
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
  check_term(v.String("hello"))
  check_term(v.LinkedList([]))
  check_term(v.LinkedList([v.Integer(1), v.Integer(2)]))
  check_term(v.unit())
  check_term(
    v.Record(
      dict.from_list([
        #("foo", v.String("hey")),
        #("nested", v.Record(dict.from_list([#("bar", v.String("inner"))]))),
      ]),
    ),
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
  let exp = ir.lambda("_", ir.string("hello"))

  let assert Ok(term) = run(exp, env.empty(), [], dict.new())
  capture.capture(term, Nil)
  |> run(env.empty(), [v.unit()], dict.new())
  |> should.equal(Ok(v.String("hello")))
}

pub fn nested_fn_test() {
  let exp =
    ir.lambda(
      "a",
      ir.lambda(
        "b",
        ir.apply(
          ir.apply(ir.cons(), ir.variable("a")),
          ir.apply(ir.apply(ir.cons(), ir.variable("b")), ir.tail()),
        ),
      ),
    )

  let assert Ok(term) = run(exp, env.empty(), [], dict.new())
  let captured = capture.capture(term, Nil)

  let e = env.empty()
  run(captured, e, [v.String("A"), v.String("B")], dict.new())
  |> should.equal(Ok(v.LinkedList([v.String("A"), v.String("B")])))
}

pub fn single_let_capture_test() {
  let exp =
    ir.let_("a", ir.string("external"), ir.lambda("_", ir.variable("a")))

  let assert Ok(term) = run(exp, env.empty(), [], dict.new())
  capture.capture(term, Nil)
  |> run(env.empty(), [v.unit()], dict.new())
  |> should.equal(Ok(v.String("external")))
}

// This test makes sure a given env value is captured only once
pub fn duplicate_capture_test() {
  let func =
    ir.lambda("_", ir.let_("_", ir.variable("std"), ir.variable("std")))
  let exp = ir.let_("std", ir.string("Standard"), func)

  let assert Ok(term) = run(exp, env.empty(), [], dict.new())
  capture.capture(term, Nil)
  |> should.equal(exp)
}

pub fn ordered_capture_test() {
  let exp =
    ir.let_(
      "a",
      ir.string("A"),
      ir.let_(
        "b",
        ir.string("B"),
        ir.lambda("_", ir.let_("inner", ir.variable("a"), ir.variable("b"))),
      ),
    )

  let assert Ok(term) = run(exp, env.empty(), [], dict.new())
  capture.capture(term, Nil)
  |> should.equal(exp)
}

pub fn ordered_fn_capture_test() {
  let exp =
    ir.let_(
      "a",
      ir.string("A"),
      ir.let_(
        "b",
        ir.lambda("_", ir.variable("a")),
        ir.lambda("_", ir.variable("b")),
      ),
    )

  let assert Ok(term) = run(exp, env.empty(), [], dict.new())
  capture.capture(term, Nil)
  |> should.equal(exp)
}

pub fn capture_shadowed_variable_test() {
  let exp =
    ir.let_(
      "a",
      ir.string("first"),
      ir.let_("a", ir.string("second"), ir.lambda("_", ir.variable("a"))),
    )

  let assert Ok(term) = run(exp, env.empty(), [], dict.new())
  capture.capture(term, Nil)
  |> run(env.empty(), [v.unit()], dict.new())
  |> should.equal(Ok(v.String("second")))
}

pub fn only_needed_values_captured_test() {
  let exp =
    ir.let_(
      "a",
      ir.string("ignore"),
      ir.let_(
        "b",
        ir.lambda("_", ir.variable("a")),
        ir.let_("c", ir.string("yes"), ir.lambda("_", ir.variable("c"))),
      ),
    )

  let assert Ok(term) = run(exp, env.empty(), [], dict.new())
  capture.capture(term, Nil)
  |> should.equal(ir.let_(
    "c",
    ir.string("yes"),
    ir.lambda("_", ir.variable("c")),
  ))
}

pub fn double_catch_test() {
  let exp =
    ir.let_(
      "std",
      ir.string("Standard"),
      ir.let_(
        "f0",
        ir.lambda("_", ir.variable("std")),
        ir.let_(
          "f1",
          ir.lambda("_", ir.variable("f0")),
          ir.let_(
            "f2",
            ir.lambda("_", ir.variable("std")),
            ir.list([ir.variable("f1"), ir.variable("f2")]),
          ),
        ),
      ),
    )

  let assert Ok(term) = run(exp, env.empty(), [], dict.new())
  capture.capture(term, Nil)
  |> should.equal(ir.let_(
    "std",
    ir.string("Standard"),
    ir.let_(
      "f0",
      ir.lambda("_", ir.variable("std")),
      // Always inlineing functions can make output quite large, although much smaller without environment.
      // A possible solution is to always lambda lift if assuming function are large parts of AST
      ir.list([
        ir.lambda("_", ir.variable("f0")),
        ir.lambda("_", ir.variable("std")),
      ]),
    ),
  ))
}

pub fn fn_in_env_test() {
  let exp =
    ir.let_(
      "a",
      ir.string("value"),
      ir.let_(
        "a",
        ir.lambda("_", ir.variable("a")),
        ir.lambda("_", ir.apply(ir.variable("a"), ir.empty())),
      ),
    )

  let assert Ok(term) = run(exp, env.empty(), [], dict.new())
  capture.capture(term, Nil)
  |> run(env.empty(), [v.unit()], dict.new())
  |> should.equal(Ok(v.String("value")))
}

pub fn tagged_test() {
  let exp = ir.tag("Ok")
  let env = env.empty()
  let assert Ok(term) = run(exp, env, [], dict.new())

  let arg = v.String("later")
  capture.capture(term, Nil)
  |> run(env.empty(), [arg], dict.new())
  |> should.equal(Ok(v.Tagged("Ok", arg)))
}

pub fn case_test() {
  let exp =
    ir.apply(
      ir.apply(ir.case_("Ok"), ir.lambda("_", ir.string("good"))),
      ir.apply(
        ir.apply(ir.case_("Error"), ir.lambda("_", ir.string("bad"))),
        ir.nocases(),
      ),
    )

  let assert Ok(term) = run(exp, env.empty(), [], dict.new())
  let next = capture.capture(term, Nil)

  let arg = v.Tagged("Ok", v.unit())
  next
  |> run(env.empty(), [arg], dict.new())
  |> should.equal(Ok(v.String("good")))

  let arg = v.Tagged("Error", v.unit())
  next
  |> run(env.empty(), [arg], dict.new())
  |> should.equal(Ok(v.String("bad")))
}

pub fn partial_case_test() {
  let exp = ir.apply(ir.case_("Ok"), ir.lambda("_", ir.string("good")))

  let assert Ok(term) = run(exp, env.empty(), [], dict.new())
  let rest =
    ir.apply(
      ir.apply(ir.case_("Error"), ir.lambda("_", ir.string("bad"))),
      ir.nocases(),
    )

  let assert Ok(rest) = run(rest, env.empty(), [], dict.new())

  let next = capture.capture(term, Nil)

  let arg = v.Tagged("Ok", v.unit())
  let e = env.empty()
  run(next, e, [rest, arg], dict.new())
  |> should.equal(Ok(v.String("good")))

  let arg = v.Tagged("Error", v.unit())
  run(next, e, [rest, arg], dict.new())
  |> should.equal(Ok(v.String("bad")))
}

pub fn handler_test() {
  let exp =
    ir.apply(
      ir.handle("Abort"),
      ir.lambda(
        "value",
        ir.lambda("_k", ir.apply(ir.tag("Error"), ir.variable("value"))),
      ),
    )

  let assert Ok(term) = run(exp, env.empty(), [], dict.new())
  let next = capture.capture(term, Nil)

  let exec = ir.lambda("_", ir.apply(ir.tag("Ok"), ir.string("some string")))

  let assert Ok(exec) = run(exec, env.empty(), [], dict.new())

  next
  |> run(env.empty(), [exec], dict.new())
  |> should.equal(Ok(v.Tagged("Ok", v.String("some string"))))

  let exec = ir.lambda("_", ir.apply(ir.perform("Abort"), ir.string("failure")))

  let assert Ok(exec) = run(exec, env.empty(), [], dict.new())

  next
  |> run(env.empty(), [exec], dict.new())
  |> should.equal(Ok(v.Tagged("Error", v.String("failure"))))
}

// pub fn capture_resume_test() {
//   let handler =
//     ir.lambda(
//       "message",
//       // ir.lambda("k", ir.apply(ir.tag("Stopped"), ir.variable("k"))),
//       ir.lambda("k", ir.variable("k")),
//     )

//   let exec =
//     ir.lambda(
//       "_",
//       ir.let_(
//         "_",
//         ir.apply(ir.perform("Log"), ir.string("first")),
//         ir.let_("_", ir.apply(ir.perform("Log"), ir.string("second")), ir.integer(0)),
//       ),
//     )
//   let exp = ir.apply(ir.apply(ir.handle("Log"), handler), exec)
//   let assert Ok(term) = r.execute(exp, env.empty(), dict.new())
//   let next = capture.capture(term,Nil)

//   next
//   |> r.execute(env.empty(), r.eval_call(_, v.String("fooo"), [], env.empty(), dict.new()))
//   // This should return a effect of subsequent logs, I don't know how to do this
// }

pub fn builtin_arity1_test() {
  let env = stdlib.env()
  let exp = ir.builtin("list_pop")
  let assert Ok(term) = run(exp, env, [], dict.new())
  let next = capture.capture(term, Nil)

  let split =
    v.Tagged(
      "Ok",
      v.Record(
        dict.from_list([
          #("head", v.Integer(1)),
          #("tail", v.LinkedList([v.Integer(2)])),
        ]),
      ),
    )
  next
  |> run(env, [v.LinkedList([v.Integer(1), v.Integer(2)])], dict.new())
  |> should.equal(Ok(split))

  // same as complete eval
  let exp =
    ir.apply(
      exp,
      ir.apply(
        ir.apply(ir.cons(), ir.integer(1)),
        ir.apply(ir.apply(ir.cons(), ir.integer(2)), ir.tail()),
      ),
    )

  run(exp, stdlib.env(), [], dict.new())
  |> should.equal(Ok(split))
}

pub fn builtin_arity3_test() {
  let env = stdlib.env()
  let list =
    ir.apply(
      ir.apply(ir.cons(), ir.integer(1)),
      ir.apply(ir.apply(ir.cons(), ir.integer(2)), ir.tail()),
    )
  let exp = ir.apply(ir.apply(ir.builtin("list_fold"), list), ir.integer(0))

  let assert Ok(term) = run(exp, env, [], dict.new())
  let next = capture.capture(term, Nil)

  let ret = run(next, env, [v.String("not a function")], dict.new())
  let assert Error(#(break.NotAFunction(v.String("not a function")), Nil, _, _)) =
    ret

  let reduce_exp = ir.lambda("el", ir.lambda("acc", ir.variable("el")))
  let assert Ok(reduce) = run(reduce_exp, env, [], dict.new())
  next
  |> run(env, [reduce], dict.new())
  |> should.equal(Ok(v.Integer(2)))

  // same as complete eval
  let exp = ir.apply(exp, reduce_exp)

  run(exp, env, [], dict.new())
  |> should.equal(Ok(v.Integer(2)))
}
