import gleam/javascript/promise.{Promise}

@external(javascript, "../../plinth_ffi.js", "wait")
pub fn wait(a: Int) -> Promise(Nil)
