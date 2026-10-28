//// Bun global API: https://bun.sh/docs/api/utils

pub type Bun

@external(javascript, "./runtime_ffi.mjs", "get")
pub fn get() -> Result(Bun, Nil)

@external(javascript, "./runtime_ffi.mjs", "collect")
pub fn collect(bun: Bun, force: Bool) -> Nil
