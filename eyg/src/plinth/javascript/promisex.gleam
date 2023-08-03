import gleam/javascript/promise

@external(javascript, "../../plinth_ffi.js", "setTimeout")
fn set_timeout(callback: fn(Nil) -> Nil, delay: Int) -> Nil

pub fn wait(delay) {
  promise.new(fn(resolve) { set_timeout(resolve, delay) })
}
