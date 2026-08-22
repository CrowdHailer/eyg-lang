import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/value as v
import gleam/dict
import gleeunit/should
import morph/analysis

pub fn builtin_to_type_test() {
  let bindings = dict.new()
  let #(t, _b) =
    v.Partial(v.Builtin("string_uppercase"), [])
    |> analysis.value_to_type(bindings, Nil)
  t
  |> should.equal(t.Fun(t.String, t.Empty, t.String))
}

pub fn partially_applied_builtin_to_type_test() {
  let bindings = dict.new()
  let #(t, _b) =
    v.Partial(v.Builtin("int_add"), [v.Integer(1)])
    |> analysis.value_to_type(bindings, Nil)
  t
  |> should.equal(t.Fun(t.Integer, t.Empty, t.Integer))
}

pub fn partially_applied_polymorphic_builtin_to_type_test() {
  let bindings = dict.new()
  let #(t, _b) =
    v.Partial(v.Builtin("equal"), [v.unit()])
    |> analysis.value_to_type(bindings, Nil)
  t
  |> should.equal(t.Fun(t.unit, t.Empty, t.boolean))
}
