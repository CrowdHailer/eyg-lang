import gleam/io
import gleam/map
import eyg/analysis/typ as t
import harness/ffi/spec
import harness/ffi/core
import plinth/browser/window

pub fn init() {
  #(t.Closed, map.new())
}

pub fn extend(state, label, parts) {
  let #(eff, handlers) = state
  let #(from, to, handler) = parts
  let eff = t.Extend(label, #(from, to), eff)
  let handlers = map.insert(handlers, label, handler)
  #(eff, handlers)
}

fn for(lift, reply, handler) {
  let assert #(t.Fun(from, _effects, to), value) =
    spec.lambda(lift, reply)
    |> spec.build(handler)
  #(from, to, value)
}

pub fn equal() {
  let t = spec.unbound()
  for(
    spec.record(spec.field("left", t, spec.field("right", t, spec.empty()))),
    spec.union(spec.variant(
      "True",
      spec.record(spec.empty()),
      spec.variant("False", spec.record(spec.empty()), spec.end()),
    )),
    fn(args) {
      fn(true) {
        fn(false) {
          let #(left, #(right, Nil)) = args
          case left == right {
            True -> true(Nil)
            False -> false(Nil)
          }
        }
      }
    },
  )
}

pub fn debug_logger() {
  let handler = fn(message) {
    io.debug(message)
    Nil
  }

  for(spec.string(), spec.record(spec.empty()), handler)
}

pub fn window_alert() {
  let handler = fn(message) {
    window.alert(message)
    Nil
  }

  for(spec.string(), spec.record(spec.empty()), handler)
}
