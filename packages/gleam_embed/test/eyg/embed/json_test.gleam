import eyg/analysis/type_/isomorphic as t
import eyg/embed/json
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/dict
import gleam/json as gleam_json

fn parse_type(raw) {
  let assert Ok(type_) = gleam_json.parse(raw, json.type_decoder())
  type_
}

pub fn types_are_described_with_plain_data_test() {
  assert parse_type("\"integer\"") == t.Integer
  assert parse_type("{\"list\": \"boolean\"}") == t.List(t.boolean)
  assert parse_type("{\"record\": {\"id\": \"integer\"}}")
    == t.record([#("id", t.Integer)])
  assert parse_type("{\"result\": {\"ok\": \"unit\", \"error\": \"string\"}}")
    == t.result(t.unit, t.String)
}

pub fn values_cross_as_plain_json_test() {
  let value =
    v.Record(
      dict.from_list([
        #("done", v.true()),
        #("tags", v.LinkedList([v.String("a")])),
        #("result", v.error(v.Tagged("NotFound", v.unit()))),
      ]),
    )
  let assert Ok(encoded) = json.to_json(value)
  let encoded = gleam_json.to_string(encoded)
  assert gleam_json.parse(encoded, json.value_decoder()) == Ok(value)
}

pub fn a_tag_without_a_value_carries_unit_test() {
  assert gleam_json.parse("{\"$\": \"None\"}", json.value_decoder())
    == Ok(v.none())
}

pub fn replies_are_checked_against_the_declared_type_test() {
  let type_ = t.record([#("id", t.Integer)])
  assert json.conforms(v.Record(dict.from_list([#("id", v.Integer(1))])), type_)
  assert !json.conforms(
    v.Record(dict.from_list([#("id", v.String("1"))])),
    type_,
  )
  assert !json.conforms(v.Record(dict.new()), type_)
}

pub fn effects_are_labels_with_two_types_test() {
  assert gleam_json.parse(
      "{\"Add\": {\"lift\": \"integer\", \"lower\": {\"list\": \"string\"}}}",
      json.effects_decoder(),
    )
    == Ok([#("Add", #(t.Integer, t.List(t.String)))])
}

pub fn a_type_that_is_not_described_is_an_error_test() {
  let assert Error(_) =
    gleam_json.parse("{\"tuple\": \"integer\"}", json.type_decoder())
  let assert Error(_) = gleam_json.parse("\"float\"", json.type_decoder())
}

pub fn a_function_cannot_be_json_test() {
  let assert Error(_) = json.to_json(v.Closure("x", ir.variable("x"), []))
}

pub fn unsafe_integers_are_rejected_at_every_boundary_test() {
  let assert Error(_) =
    gleam_json.parse("9007199254740993", json.value_decoder())
  let unsafe = v.Integer(9_007_199_254_740_991 + 1)
  assert !json.conforms(unsafe, t.Integer)
  let assert Error(_) = json.to_json(unsafe)
  let assert Ok(_) = gleam_json.parse("-9007199254740991", json.value_decoder())
}

pub fn reserved_tag_fields_cannot_silently_drop_record_data_test() {
  let assert Error(_) =
    json.to_json(v.Record(dict.from_list([#("$", v.String("Ok"))])))
  let assert Error(_) =
    gleam_json.parse(
      "{\"$\":\"Ok\",\"value\":1,\"extra\":2}",
      json.value_decoder(),
    )
  let assert Error(_) = gleam_json.parse("{\"$\":42}", json.value_decoder())
  let assert Error(_) =
    gleam_json.parse("{\"field\":null}", json.value_decoder())
}

pub fn malformed_types_and_non_eyg_json_values_fail_test() {
  let assert Error(_) =
    gleam_json.parse("{\"result\":{\"ok\":\"unit\"}}", json.type_decoder())
  let assert Error(_) =
    gleam_json.parse(
      "{\"result\":{\"ok\":\"unit\",\"error\":\"string\",\"extra\":\"integer\"}}",
      json.type_decoder(),
    )
  let assert Error(_) = gleam_json.parse("1.5", json.value_decoder())
  let assert Error(_) = gleam_json.parse("null", json.value_decoder())
  assert json.to_json(v.Binary(<<1>>))
    == Error("binary values cannot be passed as JSON")
}

pub fn nested_tagged_replies_and_closed_record_shapes_are_checked_test() {
  let type_ =
    parse_type(
      "{\"result\":{\"ok\":{\"list\":{\"record\":{\"id\":\"integer\"}}},\"error\":\"string\"}}",
    )
  let value =
    v.ok(v.LinkedList([v.Record(dict.from_list([#("id", v.Integer(1))]))]))
  assert json.conforms(value, type_)
  assert !json.conforms(
    v.ok(v.LinkedList([v.Record(dict.from_list([#("id", v.String("1"))]))])),
    type_,
  )
  assert !json.conforms(v.error(v.Integer(1)), type_)
  assert !json.conforms(v.Tagged("Other", v.unit()), type_)
  assert !json.conforms(
    v.Record(dict.from_list([#("id", v.Integer(1)), #("extra", v.unit())])),
    t.record([#("id", t.Integer)]),
  )
}
