import gleam/javascript/promise.{Promise}

pub external fn wait(Int) -> Promise(Nil) =
  "../../plinth_ffi.js" "wait"
