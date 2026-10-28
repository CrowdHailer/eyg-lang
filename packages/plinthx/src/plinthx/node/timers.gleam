//// Node timers: https://nodejs.org/api/timers.html#timerspromisessettimeoutdelay-value-options

import gleam/javascript/promise.{type Promise}

@external(javascript, "./timers_ffi.mjs", "sleep")
pub fn sleep(milliseconds: Int) -> Promise(Nil)

pub type Timeout

@external(javascript, "./timers_ffi.mjs", "setTimeout")
pub fn set_timeout(milliseconds: Int, callback: fn() -> Nil) -> Timeout

@external(javascript, "./timers_ffi.mjs", "clearTimeout")
pub fn clear_timeout(timeout: Timeout) -> Nil
