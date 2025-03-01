import eyg/interpreter/value as v
import gleam/dict
import gleam/javascript/promise
import gleeunit/should
import website/harness/json

pub fn do(data) {
  json.blocking(v.Binary(<<data:utf8>>))
  |> should.be_ok
}

pub fn decode_primitives_test() {
  use v <- promise.map(do("true"))
  should.equal(v, v.ok(v.Tagged("True", v.unit())))
  use v <- promise.map(do("false"))
  should.equal(v, v.ok(v.Tagged("False", v.unit())))
  // use v <- promise.map(do("null"))
  // should.equal(v, v.ok(v.Tagged("False", v.unit())))
}

pub fn decode_nested_object_test() {
  use v <- promise.map(do("{\"a\":{\"b\":{}},\"x\":{}}"))
  should.equal(
    v,
    v.ok(
      v.Record(
        dict.from_list([
          #(
            "a",
            v.Record(dict.from_list([#("b", v.Record(dict.from_list([])))])),
          ),
          #("x", v.Record(dict.from_list([]))),
        ]),
      ),
    ),
  )
  // use v <- promise.map(do("null"))
  // should.equal(v, v.ok(v.Tagged("False", v.unit())))
}
