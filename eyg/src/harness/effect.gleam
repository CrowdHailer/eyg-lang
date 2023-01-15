import gleam/io
import gleam/map
import eyg/analysis/typ as t
import harness/ffi/spec

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
  assert #(t.Fun(from, _effects, to), value) =
    spec.lambda(lift, reply)
    |> spec.build(handler)
  #(from, to, value)
}

pub fn debug_logger() {
  let handler = fn(message) {
    io.debug(message)
    Nil
  }

  for(spec.string(), spec.record(spec.empty()), handler)
}
