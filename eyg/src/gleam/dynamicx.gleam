import gleam/dynamic.{type Dynamic}

pub fn from(a) -> Dynamic {
  do_from(a)
}

@external(javascript, "../gleam_dynamicx.mjs", "identity")
fn do_from(a: anything) -> Dynamic

pub fn unsafe_coerce(a: Dynamic) -> anything {
  do_unsafe_coerce(a)
}

@external(javascript, "../gleam_dynamicx.mjs", "identity")
fn do_unsafe_coerce(a: Dynamic) -> a
