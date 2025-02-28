import eyg/interpreter/state as s
import eyg/interpreter/value as v
import gleam/dynamic
import gleam/dynamicx
import gleam/list
import harness/stdlib

pub fn execute(exp, h) {
  let env = dynamicx.unsafe_coerce(dynamic.from(stdlib.env()))
  loop(s.step(s.E(exp), env, s.Empty(h)), [])
}

pub fn loop(next, acc) {
  case next {
    s.Loop(c, e, k) -> {
      let acc = case c, k {
        s.V(v), s.Stack(s.Apply(v.Closure(x, #(_body, meta), _), _), _, ..)
        | // Doesn't work with !list_fold more investigation needed
          // | s.V(v), s.Stack(s.CallWith(v.Closure(x, #(_body, meta), _), _), _, ..)
          s.V(v),
          s.Stack(
            s.Assign(x, _, _),
            meta,
            ..,
          )
        -> {
          let #(start, _) = meta
          //   +1 is a hack for my current span intersection logic
          [#(x, v, #(start, start + 1)), ..acc]
        }
        // I think CallWith also needed
        _, _ -> acc
      }
      loop(s.step(c, e, k), acc)
    }
    s.Break(result) -> #(result, list.reverse(acc))
  }
}
