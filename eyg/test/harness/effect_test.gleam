import gleam/io
import gleam/mapx
import eygir/expression as e
import eyg/runtime/interpreter as r
import eyg/runtime/capture
import harness/effect
import gleeunit/should

fn effect_eval(exp, extrinsic) {
  r.handle(r.eval(exp, [], r.Value), extrinsic)
}

// With Effects there is the issue of genericification of the equal fn
// A bounce effect you raise and drop the same thing
// the handlers are equivalent to let so is where we generalize
// But a function might well have two equality checks and not know ahead of time what they will be
// What is the goal here. FFI worked before but no deploy/resumption
// polymorphic effects are described because of the usage of rows
// Is there a forall A fn(A,A)<FFI_EQUAL(A)> True | False
pub fn equal_test() {
  let #(lift, resume, handle) = effect.equal()
  // |> io.debug
  let exp =
    e.Apply(
      e.Perform("FFI_Equal"),
      e.Apply(
        e.Apply(e.Extend("left"), e.Integer(1)),
        e.Apply(e.Apply(e.Extend("right"), e.Integer(2)), e.Empty),
      ),
    )
  effect_eval(exp, mapx.singleton("FFI_Equal", handle))
  |> io.debug
}
