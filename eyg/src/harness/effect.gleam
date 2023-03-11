import gleam/io
import gleam/map
import eyg/analysis/typ as t
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

pub fn debug_logger() {
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
