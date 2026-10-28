//// DOM AbortSignal: https://dom.spec.whatwg.org/#interface-abortsignal

pub type Constructor

pub type AbortSignal

@external(javascript, "./abort_signal_ffi.mjs", "get")
pub fn get() -> Result(Constructor, Nil)

@external(javascript, "./abort_signal_ffi.mjs", "timeout")
pub fn timeout(
  constructor: Constructor,
  milliseconds: Int,
) -> Result(AbortSignal, String)
