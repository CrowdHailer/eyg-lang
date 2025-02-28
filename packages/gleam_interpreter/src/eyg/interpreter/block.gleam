import eyg/interpreter/expression
import eyg/interpreter/state
import eyg/ir/tree as ir
import gleam/dict
import gleam/list
import gleam/option.{None, Some}

const special = "!!special!!"

// env is top env only updated by assigns
fn loop(next, env) {
  case next {
    state.Loop(c, e, k) -> {
      // update top env
      case c, k {
        state.V(_v), state.Stack(state.Assign(l, _then, env), _, state.Empty(_))
          if l == special
        -> {
          loop(state.step(c, e, k), env.scope)
        }
        state.E(#(ir.Vacant, _)), state.Empty(_) -> Ok(#(None, env))
        _, _ -> loop(state.step(c, e, k), env)
      }
    }
    state.Break(Ok(result)) -> Ok(#(Some(result), env))
    state.Break(Error(reason)) -> Error(reason)
  }
}

pub fn inject(exp, acc) {
  case exp {
    #(ir.Let(l, v, t), m) -> inject(t, [#(l, m, v), ..acc])
    _ -> {
      let acc = [#(special, Nil, #(ir.Empty, Nil)), ..acc]
      list.fold(acc, exp, fn(exp, assign) {
        let #(l, m, v) = assign
        #(ir.Let(l, v, exp), m)
      })
    }
  }
}

pub fn execute(exp, scope) {
  let exp = inject(exp, [])
  let env = expression.new_env(scope)
  let h = dict.new()
  loop(state.step(state.E(exp), env, state.Empty(h)), env.scope)
}

pub fn call(f, args, env, h) {
  let k =
    list.fold_right(args, state.Empty(h), fn(k, arg) {
      let #(value, meta) = arg
      state.Stack(state.CallWith(value, env), meta, k)
    })
  loop(state.step(state.V(f), env, k), env.scope)
}

pub fn resume(value, env, k) {
  loop(state.step(state.V(value), env, k), env.scope)
}
