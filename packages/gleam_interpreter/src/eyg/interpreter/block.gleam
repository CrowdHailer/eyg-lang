import eyg/interpreter/builtin
import eyg/interpreter/state
import eyg/ir/tree as ir
import gleam/list
import gleam/option.{type Option, None, Some}

const special = "!!special!!"

// env is top env only updated by assigns
fn loop(next, env) {
  case next {
    state.Loop(c, e, k) -> {
      // update top env
      case c, k {
        state.V(_v), state.Stack(state.Assign(l, _then, env), _, state.Empty)
          if l == special
        -> {
          loop(state.step(c, e, k), env.scope)
        }
        state.E(#(ir.Vacant, _)), state.Empty -> Ok(#(None, env))
        _, _ -> loop(state.step(c, e, k), env)
      }
    }
    state.Break(Ok(result)) -> Ok(#(Some(result), env))
    state.Break(Error(reason)) -> Error(reason)
  }
}

fn inject(exp: ir.Node(t), acc: List(#(String, t, ir.Node(t)))) -> ir.Node(t) {
  case exp {
    #(ir.Let(l, v, t), m) -> inject(t, [#(l, m, v), ..acc])
    #(_, m) -> {
      let acc = [#(special, m, #(ir.Empty, m)), ..acc]
      list.fold(acc, exp, fn(exp, assign) {
        let #(l, m, v) = assign
        #(ir.Let(l, v, exp), m)
      })
    }
  }
}

/// Exectute a block of code.
/// If there is no final expression no value is returned.
/// 
/// In all cases a scope is returned this can be used for builting REPL's
pub fn execute(
  exp: ir.Node(t),
  scope: state.Scope(t),
) -> Result(#(Option(state.Value(t)), state.Scope(t)), state.Debug(t)) {
  let exp = inject(exp, [])
  let env = builtin.default(scope)

  loop(state.step(state.E(exp), env, state.Empty), env.scope)
}

/// Call an evaluated function with arguments 
pub fn call(f, args, env) {
  let k =
    list.fold_right(args, state.Empty, fn(k, arg) {
      let #(value, meta) = arg
      state.Stack(state.CallWith(value, env), meta, k)
    })
  loop(state.step(state.V(f), env, k), env.scope)
}

/// Resume the interpretation loop with a value from a previous break position.
/// This can be used to resume after any break but is normally used to implement
/// effects and reference lookup
pub fn resume(
  value: state.Value(t),
  env: state.Env(t),
  k: state.Stack(t),
) -> Result(#(Option(state.Value(t)), state.Scope(t)), state.Debug(t)) {
  loop(state.step(state.V(value), env, k), env.scope)
}
