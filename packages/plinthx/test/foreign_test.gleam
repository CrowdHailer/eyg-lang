import gleam/dynamic
import gleam/dynamic/decode
import gleam/javascript/array
import plinthx/javascript/foreign

pub fn native_arrays_objects_and_functions_cross_the_dynamic_boundary_test() {
  let items =
    foreign.to_dynamic(array.from_list([dynamic.int(1), dynamic.int(2)]))
  assert foreign.length(items) == 2
  assert foreign.index(items, 1) == dynamic.int(2)
  let record = foreign.object(array.from_list([#("answer", dynamic.int(42))]))
  assert decode.run(record, decode.field("answer", decode.int, decode.success))
    == Ok(42)
  let function = foreign.to_dynamic(fn(value) { value })
  assert foreign.is_function(function)
  assert !foreign.is_function(record)
  assert foreign.apply(function, array.from_list([record])) == record
}

pub fn a_wrapped_function_delegates_calls_and_keeps_its_original_body_test() {
  let body = foreign.to_dynamic(fn(value) { value })
  let wrapped =
    foreign.wrap(body, fn(self, value) {
      assert foreign.has_body(self)
      assert foreign.body(self) == body
      value
    })
  assert foreign.has_body(wrapped)
  assert !foreign.has_body(body)
  assert foreign.body(body) == body
  assert foreign.apply(wrapped, array.from_list([dynamic.int(42)]))
    == dynamic.int(42)
}
