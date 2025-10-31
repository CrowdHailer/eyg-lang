import gleam/javascript/promise.{type Promise}

@external(erlang, "eyg_ir_promise_ffi", "map")
pub fn map(p: Promise(t), then: fn(t) -> u) -> Promise(u) {
  promise.map(p, then)
}

@external(erlang, "eyg_ir_promise_ffi", "identity")
pub fn await_list(ps: List(Promise(t))) -> Promise(List(t)) {
  promise.await_list(ps)
}
