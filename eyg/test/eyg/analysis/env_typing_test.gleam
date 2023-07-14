import gleam/io
import gleam/list
import gleam/map
import gleam/set
import eyg/analysis/jm/tree
import eyg/analysis/jm/infer
import eyg/analysis/jm/type_ as t
import eyg/analysis/jm/env as tenv
import eygir/expression as e
import eyg/runtime/interpreter as r
import gleeunit/should

fn runtime_to_type_env(env: List(#(String, r.Term))) -> tenv.Env {
  do_transfer(list.reverse(env), map.new())
  //   // ignore builtins assume they are the same
  //   let scope = list.reverse(env.scope)
  //   list.fold(
  //     scope,
  //     map.new(),
  //     fn(tenv, assignment) {
  //       let #(var, term) = assignment
  //       map.insert(tenv, var, term_to_scheme(term))
  //     },
  //   )
  //   // tenv
}

// I really dont know the rules here. would you be better off adding paths to interpreter and keeping 
// envs in state
fn do_transfer(env, state) {
  case env {
    [] -> state
    [#(key, term), ..rest] -> {
      let type_ = case term {
        r.Integer(_) -> t.Integer
        r.Binary(_) -> t.String

        // r.Tagged(label, value) ->
        // t.Union(t.RowExtend(label, term_to_type(value), t.Empty))
        // r.Function(param, body, env, _) -> {
        //   let state = tree.infer(e.Lambda(param, body), t.Var(-1), t.Var(-2))
        //   let types = { state.0 }.2
        //   let assert Ok(Ok(t)) = map.get(types, [])
        //   t.resolve(t, { state.0 }.2)
        // }
        // |> io.debug
        // todo
        _ -> panic
      }
      // there is no env
      let scheme = #(
        t.ftv(type_)
        |> set.to_list,
        type_,
      )
      let state = map.insert(state, key, scheme)
      do_transfer(rest, state)
    }
  }
}

// fn term_to_scheme(term) {
//   infer.mono(term_to_type(term))
// }

pub fn simple_value_test() {
  let env =
    [#("a", r.Binary("hey")), #("b", r.Integer(1))]
    |> runtime_to_type_env

  should.equal(2, map.size(env))
  should.equal(Ok(#([], t.String)), map.get(env, "a"))
  should.equal(Ok(#([], t.Integer)), map.get(env, "b"))
}

pub fn overwrite_test() {
  let env =
    [#("a", r.Binary("hey")), #("a", r.Integer(1))]
    |> runtime_to_type_env

  should.equal(1, map.size(env))
  should.equal(Ok(#([], t.String)), map.get(env, "a"))
}

pub fn function_test() {
  let env =
    [#("a", r.Function("key", e.Variable("key"), [], []))]
    |> runtime_to_type_env

  should.equal(1, map.size(env))
  should.equal(
    Ok(#([0, 1], t.Fun(t.Var(0), t.Var(1), t.Var(0)))),
    map.get(env, "a"),
  )
}
