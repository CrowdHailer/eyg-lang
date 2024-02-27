import gleam/dict
import gleam/javascript/promise
import gleeunit/should
import eygir/expression as e
import eygir/annotated as e2
import eyg/runtime/interpreter/runner as r
import eyg/runtime/interpreter/state
import eyg/runtime/value as v
import eyg/runtime/break
import harness/ffi/env
import harness/effect
import harness/stdlib
import platforms/browser

pub fn variable_test() {
  let source =
    e.Variable("x")
    |> e2.add_meta(Nil)
  let env = state.Env([#("x", v.Str("assigned"))], dict.new())
  r.execute(source, env, dict.new())
  |> should.equal(Ok(v.Str("assigned")))
}

pub fn function_test() {
  let body = e.Variable("x")
  let source =
    e.Lambda("x", body)
    |> e2.add_meta(Nil)

  let scope = [#("foo", v.Str("assigned"))]
  let env = state.Env(scope, dict.new())
  r.execute(source, env, dict.new())
  |> should.equal(
    Ok(v.Closure(
      "x",
      body
      |> e2.add_meta(Nil),
      scope,
    )),
  )
}

pub fn function_application_test() {
  let source =
    e.Apply(e.Lambda("x", e.Str("body")), e.Integer(0))
    |> e2.add_meta(Nil)

  r.execute(source, env.empty(), dict.new())
  |> should.equal(Ok(v.Str("body")))

  let source =
    e.Let(
      "id",
      e.Lambda("x", e.Variable("x")),
      e.Apply(e.Variable("id"), e.Integer(0)),
    )
    |> e2.add_meta(Nil)

  r.execute(source, env.empty(), dict.new())
  |> should.equal(Ok(v.Integer(0)))
}
// pub fn builtin_application_test() {
//   let source = e.Apply(e.Builtin("string_uppercase"), e.Str("hello"))

//   r.execute(source, stdlib.env(), dict.new())
//   |> should.equal(Ok(v.Str("HELLO")))
// }

// // primitive
// pub fn create_a_binary_test() {
//   let source = e.Str("hello")
//   r.execute(source, env.empty(), dict.new())
//   |> should.equal(Ok(v.Str("hello")))
// }

// pub fn create_an_integer_test() {
//   let source = e.Integer(5)
//   r.execute(source, env.empty(), dict.new())
//   |> should.equal(Ok(v.Integer(5)))
// }

// pub fn record_creation_test() {
//   let source = e.Empty
//   r.execute(source, env.empty(), dict.new())
//   |> should.equal(Ok(v.unit))

//   let source =
//     e.Apply(
//       e.Apply(e.Extend("foo"), e.Str("FOO")),
//       e.Apply(e.Apply(e.Extend("bar"), e.Integer(0)), e.Empty),
//     )
//   r.execute(e.Apply(e.Select("foo"), source), env.empty(), dict.new())
//   |> should.equal(Ok(v.Str("FOO")))
//   r.execute(e.Apply(e.Select("bar"), source), env.empty(), dict.new())
//   |> should.equal(Ok(v.Integer(0)))
// }

// pub fn case_test() {
//   let switch =
//     e.Apply(
//       e.Apply(e.Case("Some"), e.Lambda("x", e.Variable("x"))),
//       e.Apply(e.Apply(e.Case("None"), e.Lambda("_", e.Str("else"))), e.NoCases),
//     )

//   let source = e.Apply(switch, e.Apply(e.Tag("Some"), e.Str("foo")))
//   r.execute(source, env.empty(), dict.new())
//   |> should.equal(Ok(v.Str("foo")))

//   let source = e.Apply(switch, e.Apply(e.Tag("None"), e.Empty))
//   r.execute(source, env.empty(), dict.new())
//   |> should.equal(Ok(v.Str("else")))
// }

// pub fn rasing_effect_test() {
//   let source =
//     e.Let(
//       "a",
//       e.Apply(e.Perform("Foo"), e.Integer(1)),
//       e.Apply(e.Perform("Bar"), e.Variable("a")),
//     )
//   let assert Error(#(break.UnhandledEffect("Foo", lifted), rev, env, k)) =
//     r.execute(source, env.empty(), dict.new())
//   lifted
//   |> should.equal(v.Integer(1))
//   let assert Error(#(break.UnhandledEffect("Bar", lifted), rev, env, k)) =
//     r.loop(state.step(state.V(v.Str("reply")), rev, env, k))
//   lifted
//   |> should.equal(v.Str("reply"))
//   let assert Ok(term) = r.loop(state.step(state.V(v.unit), rev, env, k))
//   term
//   |> should.equal(v.unit)
// }

// pub fn effect_in_case_test() {
//   let switch =
//     e.Apply(
//       e.Apply(e.Case("Ok"), e.Lambda("x", e.Variable("x"))),
//       e.Apply(e.Apply(e.Case("Error"), e.Perform("Raise")), e.NoCases),
//     )

//   let source = e.Apply(switch, e.Apply(e.Tag("Ok"), e.Str("foo")))
//   r.execute(source, env.empty(), dict.new())
//   |> should.equal(Ok(v.Str("foo")))

//   let source = e.Apply(switch, e.Apply(e.Tag("Error"), e.Str("nope")))
//   let assert Error(#(break.UnhandledEffect("Raise", lifted), _rev, _env, _k)) =
//     r.execute(source, env.empty(), dict.new())
//   lifted
//   |> should.equal(v.Str("nope"))
// }

// pub fn effect_in_builtin_test() {
//   let list =
//     e.Apply(
//       e.Apply(e.Cons, e.Str("fizz")),
//       e.Apply(e.Apply(e.Cons, e.Str("buzz")), e.Tail),
//     )
//   let reducer =
//     e.Lambda(
//       "element",
//       e.Lambda(
//         "state",
//         e.Let(
//           "reply",
//           e.Apply(e.Perform("Foo"), e.Variable("element")),
//           e.Apply(
//             e.Apply(e.Builtin("string_append"), e.Variable("state")),
//             e.Variable("element"),
//           ),
//         ),
//       ),
//     )
//   let source =
//     e.Apply(
//       e.Apply(e.Apply(e.Builtin("list_fold"), list), e.Str("initial")),
//       reducer,
//     )
//   let assert Error(#(break.UnhandledEffect("Foo", lifted), rev, env, k)) =
//     r.execute(source, stdlib.env(), dict.new())
//   lifted
//   |> should.equal(v.Str("fizz"))
//   let assert Error(#(break.UnhandledEffect("Foo", lifted), rev, env, k)) =
//     r.loop(state.step(state.V(v.unit), rev, env, k))
//   lifted
//   |> should.equal(v.Str("buzz"))
//   r.loop(state.step(state.V(v.unit), rev, env, k))
//   |> should.equal(Ok(v.Str("initialfizzbuzz")))
// }

// pub fn handler_no_effect_test() {
//   let handler =
//     e.Lambda("x", e.Lambda("k", e.Apply(e.Tag("Error"), e.Variable("x"))))
//   let exec = e.Lambda("_", e.Apply(e.Tag("Ok"), e.Str("mystring")))
//   let source = e.Apply(e.Apply(e.Handle("Throw"), handler), exec)

//   r.execute(source, env.empty(), dict.new())
//   |> should.equal(Ok(v.Tagged("Ok", v.Str("mystring"))))

//   // shallow
//   let source = e.Apply(e.Apply(e.Shallow("Throw"), handler), exec)

//   r.execute(source, env.empty(), dict.new())
//   |> should.equal(Ok(v.Tagged("Ok", v.Str("mystring"))))
// }

// pub fn handle_early_return_effect_test() {
//   let handler =
//     e.Lambda("x", e.Lambda("k", e.Apply(e.Tag("Error"), e.Variable("x"))))
//   let exec = e.Lambda("_", e.Apply(e.Perform("Throw"), e.Str("Bad thing")))
//   let source = e.Apply(e.Apply(e.Handle("Throw"), handler), exec)

//   r.execute(source, env.empty(), dict.new())
//   |> should.equal(Ok(v.Tagged("Error", v.Str("Bad thing"))))

//   let source = e.Apply(e.Apply(e.Shallow("Throw"), handler), exec)

//   r.execute(source, env.empty(), dict.new())
//   |> should.equal(Ok(v.Tagged("Error", v.Str("Bad thing"))))
// }

// pub fn handle_resume_test() {
//   let handler =
//     e.Lambda(
//       "x",
//       e.Lambda(
//         "k",
//         e.Apply(
//           e.Apply(e.Extend("value"), e.Apply(e.Variable("k"), e.Empty)),
//           e.Apply(e.Apply(e.Extend("log"), e.Variable("x")), e.Empty),
//         ),
//       ),
//     )

//   let exec =
//     e.Lambda(
//       "_",
//       e.Let("_", e.Apply(e.Perform("Log"), e.Str("my message")), e.Integer(100)),
//     )
//   let source = e.Apply(e.Apply(e.Handle("Log"), handler), exec)

//   r.execute(source, env.empty(), dict.new())
//   |> should.equal(
//     Ok(v.Record([#("value", v.Integer(100)), #("log", v.Str("my message"))])),
//   )

//   let source = e.Apply(e.Apply(e.Shallow("Log"), handler), exec)

//   r.execute(source, env.empty(), dict.new())
//   |> should.equal(
//     Ok(v.Record([#("value", v.Integer(100)), #("log", v.Str("my message"))])),
//   )
// }

// pub fn ignore_other_effect_test() {
//   let handler =
//     e.Lambda("x", e.Lambda("k", e.Apply(e.Tag("Error"), e.Variable("x"))))
//   let exec =
//     e.Lambda(
//       "_",
//       e.Apply(
//         e.Apply(e.Extend("foo"), e.Apply(e.Perform("Foo"), e.Empty)),
//         e.Empty,
//       ),
//     )
//   let source = e.Apply(e.Apply(e.Handle("Throw"), handler), exec)

//   let assert Error(#(break.UnhandledEffect("Foo", lifted), rev, env, k)) =
//     r.execute(source, env.empty(), dict.new())
//   lifted
//   |> should.equal(v.unit)
//   // calling k should fall throu
//   // Should test wrapping binary here to check K works properly
//   r.loop(state.step(state.V(v.Str("reply")), rev, env, k))
//   |> should.equal(Ok(v.Record([#("foo", v.Str("reply"))])))

//   // SHALLOW
//   let source = e.Apply(e.Apply(e.Shallow("Throw"), handler), exec)

//   let assert Error(#(break.UnhandledEffect("Foo", lifted), rev, env, k)) =
//     r.execute(source, env.empty(), dict.new())
//   lifted
//   |> should.equal(v.unit)
//   // calling k should fall throu
//   // Should test wrapping binary here to check K works properly
//   r.loop(state.step(state.V(v.Str("reply")), rev, env, k))
//   |> should.equal(Ok(v.Record([#("foo", v.Str("reply"))])))
// }

// pub fn multiple_effects_test() {
//   let source =
//     e.Apply(
//       e.Apply(e.Extend("a"), e.Apply(e.Perform("Choose"), e.unit)),
//       e.Apply(
//         e.Apply(e.Extend("b"), e.Apply(e.Perform("Choose"), e.unit)),
//         e.Empty,
//       ),
//     )

//   let assert Error(#(break.UnhandledEffect("Choose", lifted), rev, env, k)) =
//     r.execute(source, env.empty(), dict.new())
//   lifted
//   |> should.equal(v.unit)

//   let assert Error(#(break.UnhandledEffect("Choose", lifted), rev, env, k)) =
//     r.loop(state.step(state.V(v.Str("True")), rev, env, k))
//   lifted
//   |> should.equal(v.unit)

//   r.loop(state.step(state.V(v.Str("False")), rev, env, k))
//   |> should.equal(Ok(v.Record([#("a", v.Str("True")), #("b", v.Str("False"))])))
// }

// pub fn multiple_resumptions_test() {
//   let raise =
//     e.Lambda(
//       "_",
//       e.Apply(
//         e.Apply(e.Extend("a"), e.Apply(e.Perform("Choose"), e.unit)),
//         e.Apply(
//           e.Apply(e.Extend("b"), e.Apply(e.Perform("Choose"), e.unit)),
//           e.Empty,
//         ),
//       ),
//     )
//   let handle =
//     e.Apply(
//       e.Handle("Choose"),
//       e.Lambda(
//         "_",
//         e.Lambda(
//           "k",
//           e.Apply(
//             e.Apply(e.Extend("first"), e.Apply(e.Variable("k"), e.true)),
//             e.Apply(
//               e.Apply(e.Extend("second"), e.Apply(e.Variable("k"), e.false)),
//               e.Empty,
//             ),
//           ),
//         ),
//       ),
//     )
//   let source = e.Apply(handle, raise)
//   r.execute(source, env.empty(), dict.new())
//   // Not sure this is the correct value but it checks regressions
//   |> should.equal(
//     Ok(
//       v.Record(fields: [
//         #(
//           "first",
//           v.Record([
//             #(
//               "first",
//               v.Record([
//                 #("a", v.Tagged("True", v.unit)),
//                 #("b", v.Tagged("True", v.unit)),
//               ]),
//             ),
//             #(
//               "second",
//               v.Record([
//                 #("a", v.Tagged("True", v.unit)),
//                 #("b", v.Tagged("False", v.unit)),
//               ]),
//             ),
//           ]),
//         ),
//         #(
//           "second",
//           v.Record([
//             #(
//               "first",
//               v.Record([
//                 #("a", v.Tagged("False", v.unit)),
//                 #("b", v.Tagged("True", v.unit)),
//               ]),
//             ),
//             #(
//               "second",
//               v.Record([
//                 #("a", v.Tagged("False", v.unit)),
//                 #("b", v.Tagged("False", v.unit)),
//               ]),
//             ),
//           ]),
//         ),
//       ]),
//     ),
//   )
// }

// pub fn handler_doesnt_continue_to_effect_then_in_let_test() {
//   let handler =
//     e.Apply(e.Handle("Log"), e.Lambda("lift", e.Lambda("k", e.Str("Caught"))))
//   let source =
//     e.Let(
//       "_",
//       e.Apply(handler, e.Lambda("_", e.Str("Original"))),
//       e.Apply(e.Perform("Log"), e.Str("outer")),
//     )
//   let assert Error(#(break.UnhandledEffect("Log", v.Str("outer")), rev, env, k)) =
//     r.execute(source, env.empty(), dict.new())
//   r.loop(state.step(state.V(v.unit), rev, env, k))
//   |> should.equal(Ok(v.unit))

//   let handler =
//     e.Apply(e.Shallow("Log"), e.Lambda("lift", e.Lambda("k", e.Str("Caught"))))
//   let source =
//     e.Let(
//       "_",
//       e.Apply(handler, e.Lambda("_", e.Str("Original"))),
//       e.Apply(e.Perform("Log"), e.Str("outer")),
//     )
//   let assert Error(#(break.UnhandledEffect("Log", v.Str("outer")), rev, env, k)) =
//     r.execute(source, env.empty(), dict.new())
//   r.loop(state.step(state.V(v.unit), rev, env, k))
//   |> should.equal(Ok(v.unit))
// }

// pub fn handler_is_applied_after_other_effects_test() {
//   let handler =
//     e.Apply(e.Handle("Fail"), e.Lambda("lift", e.Lambda("k", e.Integer(-1))))
//   let exec =
//     e.Lambda(
//       "_",
//       e.Let(
//         "_",
//         e.Apply(e.Perform("Log"), e.Str("my log")),
//         e.Let(
//           "_",
//           e.Apply(e.Perform("Fail"), e.Str("some error")),
//           e.Str("done"),
//         ),
//       ),
//     )

//   let source = e.Apply(handler, exec)
//   let assert Error(#(break.UnhandledEffect("Log", v.Str("my log")), rev, env, k)) =
//     r.execute(source, env.empty(), dict.new())

//   r.loop(state.step(state.V(v.unit), rev, env, k))
//   |> should.equal(Ok(v.Integer(-1)))

//   let handler =
//     e.Apply(e.Shallow("Fail"), e.Lambda("lift", e.Lambda("k", e.Integer(-1))))
//   let exec =
//     e.Lambda(
//       "_",
//       e.Let(
//         "_",
//         e.Apply(e.Perform("Log"), e.Str("my log")),
//         e.Let(
//           "_",
//           e.Apply(e.Perform("Fail"), e.Str("some error")),
//           e.Str("done"),
//         ),
//       ),
//     )

//   let source = e.Apply(handler, exec)
//   let assert Error(#(break.UnhandledEffect("Log", v.Str("my log")), rev, env, k)) =
//     r.execute(source, env.empty(), dict.new())

//   r.loop(state.step(state.V(v.unit), rev, env, k))
//   |> should.equal(Ok(v.Integer(-1)))
// }

// // async/task

// fn handlers() {
//   effect.init()
//   |> effect.extend("Async", browser.async())
// }

// pub fn async_test() {
//   let f =
//     e.Lambda("_", e.Apply(e.Perform("Async"), e.Lambda("_", e.Str("later"))))
//   let source = e.Apply(f, e.unit)
//   let assert Ok(v.Promise(p)) = r.execute(source, stdlib.env(), handlers().1)
//   use value <- promise.map(p)
//   value
//   |> should.equal(v.Str("later"))
// }
