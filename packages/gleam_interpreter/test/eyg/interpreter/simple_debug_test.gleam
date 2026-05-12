import birdie
import eyg/interpreter/simple_debug
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/dict
import gleam/int
import gleam/list

fn record(fields: List(#(String, v.Value(m, ctx)))) -> v.Value(m, ctx) {
  v.Record(dict.from_list(fields))
}

fn snapshot(value: v.Value(m, ctx), width: Int, title: String) -> Nil {
  simple_debug.render(value, width)
  |> birdie.snap(title: title)
}

pub fn integer_test() {
  snapshot(v.Integer(42), 80, "integer")
}

pub fn string_test() {
  snapshot(v.String("hello"), 80, "string")
}

pub fn string_with_escapes_test() {
  snapshot(v.String("line one\nline two\twith\ttab"), 80, "string with escapes")
}

pub fn empty_list_test() {
  snapshot(v.LinkedList([]), 80, "empty list")
}

pub fn empty_record_test() {
  snapshot(record([]), 80, "empty record")
}

pub fn small_list_fits_one_line_test() {
  snapshot(
    v.LinkedList([v.Integer(1), v.Integer(2), v.Integer(3)]),
    80,
    "small list fits on one line",
  )
}

pub fn small_record_fits_one_line_test() {
  snapshot(
    record([#("a", v.Integer(1)), #("b", v.Integer(2))]),
    80,
    "small record fits on one line",
  )
}

pub fn long_list_breaks_test() {
  let items =
    [1, 2, 3, 4, 5, 6, 7, 8]
    |> list.map(v.Integer)
  snapshot(v.LinkedList(items), 20, "long list breaks across lines")
}

pub fn long_record_breaks_test() {
  let fields =
    [1, 2, 3, 4, 5]
    |> list.map(fn(i) {
      #("field_" <> int.to_string(i), v.String("value " <> int.to_string(i)))
    })
  snapshot(record(fields), 20, "long record breaks across lines")
}

pub fn nested_record_in_list_test() {
  let items = [
    record([#("name", v.String("alice")), #("age", v.Integer(30))]),
    record([#("name", v.String("bob")), #("age", v.Integer(25))]),
  ]
  snapshot(
    v.LinkedList(items),
    40,
    "list of records breaks while inner records may fit",
  )
}

pub fn deeply_nested_test() {
  let inner = record([#("x", v.Integer(1)), #("y", v.Integer(2))])
  let middle = record([#("point", inner), #("label", v.String("origin"))])
  let outer = v.LinkedList([middle, middle])
  snapshot(outer, 30, "deeply nested structures break and indent")
}

pub fn tagged_value_test() {
  snapshot(v.Tagged("Ok", v.Integer(7)), 80, "tagged value with simple payload")
}

pub fn tagged_record_test() {
  snapshot(
    v.Tagged(
      "Person",
      record([#("name", v.String("alice")), #("age", v.Integer(30))]),
    ),
    80,
    "tagged value wrapping a record",
  )
}

pub fn tagged_partial_test() {
  snapshot(v.tag("Ok"), 80, "tag function with no value")
}

pub fn closure_test() {
  let body = ir.variable("x")
  snapshot(
    v.Closure("x", body, []),
    80,
    "closure shows parameter and ellipsis body",
  )
}

pub fn narrow_width_forces_breaks_test() {
  snapshot(
    v.LinkedList([v.Integer(1), v.Integer(2)]),
    4,
    "very narrow width forces a list to break",
  )
}
