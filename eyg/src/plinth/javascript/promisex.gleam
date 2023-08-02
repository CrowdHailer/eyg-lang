import gleam/javascript/promise.{Promise}

// @external(javascript, "../../plinth_ffi.js", "wait")
// pub fn wait(a: Int) -> Promise(Nil)

@external(javascript, "../../plinth_ffi.js", "newPromise")
pub fn new(executor: fn(fn(a) -> Nil) -> Nil) -> Promise(a)

@external(javascript, "../../plinth_ffi.js", "setTimeout")
fn set_timeout(callback: fn(Nil) -> Nil, delay: Int) -> Nil

pub fn wait(delay) {
  new(fn(resolve) { set_timeout(resolve, delay) })
}
