import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/unify
import eyg/analysis/type_/isomorphic as t
import gleam/dict
import gleeunit/should

// test that dont get stuck infinite loop
pub fn rows_with_the_same_common_tail_dont_unify_test() {
  let bindings = dict.new()
  let #(root, bindings) = binding.mono(1, bindings)

  unify.unify(
    t.RowExtend("A", t.Integer, root),
    t.RowExtend("B", t.String, root),
    1,
    bindings,
  )
  |> should.be_error()
}

pub fn effects_with_the_same_common_tail_dont_unify_test() {
  let bindings = dict.new()
  let #(root, bindings) = binding.mono(1, bindings)

  unify.unify(
    t.EffectExtend("A", #(t.Integer, t.unit), root),
    t.EffectExtend("B", #(t.String, t.unit), root),
    1,
    bindings,
  )
  |> should.be_error()
}
