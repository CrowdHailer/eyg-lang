import eyg/interpreter/value as v
import gleam/bit_array
import gleam/dict
import gleam/string
import overlay/web/tools

pub fn large_binaries_are_summarized_without_modifying_values_test() {
  let bytes = bit_array.from_string(string.repeat("video", 100_000))
  let value =
    v.ok(
      v.Record(
        dict.from_list([#("body", v.Binary(bytes)), #("status", v.Integer(200))]),
      ),
    )
  let rendered = tools.inspect_result(value)
  assert string.contains(rendered, "BinarySummary")
  assert string.contains(rendered, "500000")
  assert string.length(rendered) < 500
  let assert v.Tagged("Ok", v.Record(fields)) = value
  assert Ok(v.Binary(bytes)) == dict.get(fields, "body")
}

pub fn small_values_are_shown_in_full_test() {
  assert "[1, \"hello\"]"
    == tools.inspect_result(v.LinkedList([v.Integer(1), v.String("hello")]))
  let rendered = tools.inspect_result(v.Binary(<<1, 2, 3>>))
  assert !string.contains(rendered, "BinarySummary")
}
