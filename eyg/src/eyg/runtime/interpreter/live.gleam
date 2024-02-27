import gleam/dynamic
import gleam/dict
import gleam/list
import eyg/runtime/interpreter/state as s
import eyg/runtime/value as v
import harness/stdlib

pub fn execute(exp) {
  let env = dynamic.unsafe_coerce(dynamic.from(stdlib.env()))
  let h = dict.new()
  loop(s.step(s.E(exp), env, s.Empty(h)), [])
}

pub fn loop(next, acc) {
  case next {
    s.Loop(c, e, k) -> {
      let acc = case c, k {
        s.V(v), s.Stack(s.Apply(v.Closure(x, #(_body, meta), _), _), _, ..)
        | s.V(v), s.Stack(s.Assign(x, _, _), meta, ..) -> {
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
