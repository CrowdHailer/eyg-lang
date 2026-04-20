import eyg/interpreter/simple_debug
import eyg/interpreter/value as v
import gleam/dict
import gleeunit/should

pub fn empty_record_no_newlines_test() {
  simple_debug.inspect(v.Record(dict.new()))
  |> should.equal("{}")
}

pub fn non_empty_record_test() {
  simple_debug.inspect(v.Record(dict.from_list([#("a", v.Integer(1))])))
  |> should.equal("{\n  a: 1\n}")
}
