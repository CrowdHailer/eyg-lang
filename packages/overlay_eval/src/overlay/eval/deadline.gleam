//// Bound model work using native timer bindings and Gleam promise control.
//// The caller's error type stays unchanged.

import gleam/javascript/promise.{type Promise}
import plinthx/node/timers

pub fn within(
  work: Promise(Result(a, e)),
  milliseconds: Int,
  timeout: e,
) -> Promise(Result(a, e)) {
  case milliseconds <= 0 {
    True -> work
    False ->
      promise.new(fn(resolve) {
        let timer =
          timers.set_timeout(milliseconds, fn() { resolve(Error(timeout)) })
        let _ =
          promise.map(work, fn(value) {
            timers.clear_timeout(timer)
            resolve(value)
          })
        Nil
      })
  }
}
