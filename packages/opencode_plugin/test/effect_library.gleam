//// The Effect library used by the pinned upstream dispatcher.

import gleam/dynamic.{type Dynamic}

@external(javascript, "./effect_library_ffi.mjs", "effect")
pub fn effect() -> Dynamic

@external(javascript, "./effect_library_ffi.mjs", "context")
pub fn context() -> Dynamic
