import gleam/io
import gleam/dynamic
import gleam_extra

pub fn dynamic_function_test() {
  let f = fn(x) { x }
  assert Ok(f2) = gleam_extra.dynamic_function(dynamic.from(f))

  assert Ok(out) = f2(dynamic.from(1))
  assert Ok(1) = dynamic.int(out)

  // It errors with no easy way to create a decode error so don't bother
  assert Error([]) = gleam_extra.dynamic_function(dynamic.from([]))
}
