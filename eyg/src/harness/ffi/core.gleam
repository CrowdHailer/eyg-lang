import gleam/io
import gleam/map
import eyg/analysis/typ as t
import eygir/encode
import eyg/runtime/interpreter as r
import eyg/runtime/capture
import gleam/javascript/promise
import harness/ffi/cast

pub fn equal() {
  let type_ =
    t.Fun(t.Unbound(0), t.Open(1), t.Fun(t.Unbound(0), t.Open(2), t.boolean))
  #(type_, r.Arity2(do_equal))
}

fn do_equal(left, right, _builtins, k) {
  case left == right {
    True -> r.true
    False -> r.false
  }
  |> r.continue(k, _)
}

pub fn debug() {
  let type_ = t.Fun(t.Unbound(0), t.Open(1), t.Binary)
  #(type_, r.Arity1(do_debug))
}

fn do_debug(term, _builtins, k) {
  r.continue(k, r.Binary(r.to_string(term)))
}

pub fn fix() {
  let type_ =
    t.Fun(
      t.Fun(t.Unbound(-1), t.Open(-2), t.Unbound(-1)),
      t.Open(-3),
      t.Unbound(-1),
    )
  #(type_, r.Arity1(do_fix))
}

fn do_fix(builder, builtins, k) {
  r.eval_call(builder, r.Defunc(r.Builtin("fixed", [builder])), builtins, k)
}

pub fn fixed() {
  // I'm not sure a type ever means anything here
  // fixed is not a function you can reference directly it's just a runtime
  // value produced by the fix action
  #(
    t.Unbound(0),
    r.Arity2(fn(builder, arg, builtins, k) {
      r.eval_call(
        builder,
        r.Defunc(r.Builtin("fixed", [builder])),
        builtins,
        r.eval_call(_, arg, builtins, k),
      )
    }),
  )
}

// This should be replaced by capture which returns ast
pub fn serialize() {
  let type_ =
    t.Fun(t.Fun(t.Unbound(-1), t.Open(-2), t.Unbound(-2)), t.Open(-3), t.Binary)

  #(type_, r.Arity1(do_serialize))
}

pub fn do_serialize(term, _builtins, k) {
  let exp = capture.capture(term)
  r.continue(k, r.Binary(encode.to_json(exp)))
}

pub fn promise_then() {
  // TODO real type
  let type_ = t.Unbound(0)
  #(
    type_,
    r.Arity2(fn(_, _, _, _) {
      r.Value(r.Binary(
        "This isnt needed but means handling async is not in program",
      ))
    }),
  )
}
// // this is promise await not effect Async/Await
// // This should be called then
// fn do_then(promise, prog, builtins, k) {
//   use js_promise <- cast.promise(promise)
//   io.debug("doing awaut")
//   r.Promise(promise.map(
//     js_promise,
//     fn(resolved) {
//       io.debug(#("resolve", resolved))
//       // case resolved {
//       //   r.Value(resolved) ->
//       // TODO does this have the handlers in scope
//       // How do we get reference to handlers outside
//       // Inner request not going through log stages
//       // async does change effect scope
//       // worker wold hAVE new builtin effects
//       // just last effect different
//       // runtime design
//       // just be async default
//       // neecd channel pid for message back
//       // or global state as effect
//       // queue all the http messagge etc effects
//       // but first log ends up on outside effect
//       // async ashould put everythi last timeout zero
//       r.eval_call(prog, resolved, builtins, r.Value)
//     },
//   ))
//   //   _ -> resolved
//   // }
//   |> r.continue(k, _)
// }
