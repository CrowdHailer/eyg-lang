import gleam/io
import gleam/map
import eyg/analysis/typ as t
import harness/ffi/spec
import plinth/browser/window
import eyg/runtime/interpreter as r
import harness/ffi/cast

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

pub fn debug_logger() {
  let handler = fn(message) {
    io.debug(message)
    Nil
  }
  // for(spec.string(), spec.record(spec.empty()), handler)
  #(
    t.Binary,
    t.unit,
    fn(message, k) {
      io.debug(message)
      r.continue(k, r.unit)
    },
  )
}

pub fn window_alert() {
  let handler = fn(message) {
    window.alert(message)
    Nil
  }

  // for(spec.string(), spec.record(spec.empty()), handler)
  #(
    t.Binary,
    t.unit,
    fn(message, k) {
      use message <- cast.string(message)
      window.alert(message)
      r.continue(k, r.unit)
    },
  )
}
