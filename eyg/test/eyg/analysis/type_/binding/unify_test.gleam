import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/error
import eyg/analysis/type_/binding/unify.{unify}
import eyg/analysis/type_/isomorphic as t
import gleam/dict
import gleeunit/should

pub fn binding_types_in_tail_position_get_resolved_test() {
  let b = [
    #(0, binding.Bound(t.Integer)),
    #(1, binding.Bound(t.Empty)),
    #(2, binding.Bound(t.Record(t.RowExtend("foo", t.Var(0), t.Var(1))))),
    #(3, binding.Unbound(1)),
    #(4, binding.Unbound(1)),
  ]
  let have = t.Var(2)
  let want = t.Record(t.RowExtend("init", t.Var(4), t.Var(3)))
  unify(want, have, 1, dict.from_list(b))
  |> should.be_error
  |> should.equal(error.MissingRow("init"))
}

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
