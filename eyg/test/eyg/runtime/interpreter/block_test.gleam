import eyg/runtime/interpreter/block as r
import eyg/runtime/interpreter/state
import eyg/runtime/value as v
import eygir/annotated as a
import eygir/expression as e
import gleam/dict
import gleeunit/should
import gleeunit/shouldx

fn execute(assigns, then) {
  let h = dict.new()
  // let env = fragment.empty_env(dict.new())
  // empty env makes easier debuging. printing all builtins was ugly
  let env = state.Env([], dict.new(), dict.new())

  e.block_to_expression(assigns, then)
  |> a.add_annotation([])
  |> r.execute(env, h)
}

pub fn pure_value_test() {
  let assigns = []
  let then = e.Integer(2)
  let #(value, env) =
    execute(assigns, then)
    |> should.be_ok()
  value
  |> should.be_some()
  |> should.equal(v.Integer(2))

  env
  |> shouldx.be_empty()
}

pub fn value_from_env_test() {
  let assigns = [#("j", e.Integer(20))]
  let then = e.Variable("j")
  let #(value, env) =
    execute(assigns, then)
    |> should.be_ok()
  value
  |> should.be_some()
  |> should.equal(v.Integer(20))

  env
  |> should.equal([#("j", v.Integer(value: 20))])
}

pub fn shadowed_variable_test() {
  let assigns = [#("s", e.Integer(21)), #("s", e.Integer(22))]
  let then = e.Vacant("")
  let #(value, env) =
    execute(assigns, then)
    |> should.be_ok()
  value
  |> should.be_none()

  env
  |> should.equal([#("s", v.Integer(value: 22)), #("s", v.Integer(value: 21))])
}

pub fn fn_arg_contained_test() {
  let assigns = []
  let then = e.Apply(e.Lambda("a", e.Integer(1)), e.Str("inner"))
  let #(value, env) =
    execute(assigns, then)
    |> should.be_ok()
  value
  |> should.be_some()
  |> should.equal(v.Integer(1))

  env
  |> should.equal([])
}
