import eyg/interpreter/cast
import eyg/interpreter/state
import eyg/interpreter/value as v
import gleam/int
import gleam/result.{try}
import gleam/string

pub const equal = state.Arity2(do_equal)

fn do_equal(left, right, _meta, env, k) {
  let value = case left == right {
    True -> v.true()
    False -> v.false()
  }
  Ok(#(state.V(value), env, k))
}

pub const add = state.Arity2(do_add)

fn do_add(left, right, _meta, env, k) {
  use left <- try(cast.as_integer(left))
  use right <- try(cast.as_integer(right))
  Ok(#(state.V(v.Integer(left + right)), env, k))
}

pub const subtract = state.Arity2(do_subtract)

fn do_subtract(left, right, _meta, env, k) {
  use left <- try(cast.as_integer(left))
  use right <- try(cast.as_integer(right))
  Ok(#(state.V(v.Integer(left - right)), env, k))
}

pub const append = state.Arity2(do_append)

fn do_append(left, right, _meta, env, k) {
  use left <- try(cast.as_string(left))
  use right <- try(cast.as_string(right))
  Ok(#(state.V(v.String(string.append(left, right))), env, k))
}

pub const multiply = state.Arity2(do_multiply)

fn do_multiply(left, right, _meta, env, k) {
  use left <- try(cast.as_integer(left))
  use right <- try(cast.as_integer(right))
  Ok(#(state.V(v.Integer(left * right)), env, k))
}

pub const absolute = state.Arity1(do_absolute)

fn do_absolute(x, _meta, env, k) {
  use x <- result.then(cast.as_integer(x))
  Ok(#(state.V(v.Integer(int.absolute_value(x))), env, k))
}

pub const int_to_string = state.Arity1(do_to_string)

fn do_to_string(x, _meta, env, k) {
  use x <- result.then(cast.as_integer(x))
  Ok(#(state.V(v.String(int.to_string(x))), env, k))
}

pub const list_fold = state.Arity3(do_list_fold)

fn do_list_fold(list, state, func, meta, env, k) {
  use elements <- result.then(cast.as_list(list))
  case elements {
    [] -> Ok(#(state.V(state), env, k))
    [element, ..rest] -> {
      state.call(
        func,
        element,
        meta,
        env,
        state.Stack(
          state.CallWith(state, env),
          meta,
          state.Stack(
            state.Apply(
              v.Partial(v.Builtin("list_fold"), [v.LinkedList(rest)]),
              env,
            ),
            meta,
            state.Stack(state.CallWith(func, env), meta, k),
          ),
        ),
      )
    }
  }
}
