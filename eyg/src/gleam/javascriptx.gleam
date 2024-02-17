import gleam/javascript.{type Reference}

@external(javascript, "../javascriptx_ffi.mjs", "referenceEqual")
pub fn reference_equal(a: Reference(a), b: Reference(a)) -> Bool
