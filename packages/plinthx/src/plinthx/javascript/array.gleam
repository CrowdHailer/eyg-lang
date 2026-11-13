//// ECMAScript Array methods: https://tc39.es/ecma262/#sec-array-objects

import gleam/javascript/array.{type Array}

@external(javascript, "./array_ffi.mjs", "push")
pub fn push(array: Array(a), value: a) -> Result(Int, String)

@external(javascript, "./array_ffi.mjs", "splice")
pub fn splice(
  array: Array(a),
  start: Int,
  delete_count: Int,
  items: List(a),
) -> Result(Array(a), String)
