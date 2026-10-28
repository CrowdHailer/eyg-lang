//// ECMAScript Object identity, useful for measuring shared immutable data.

@external(javascript, "./object_ffi.mjs", "same")
pub fn is_same(left: a, right: a) -> Bool
