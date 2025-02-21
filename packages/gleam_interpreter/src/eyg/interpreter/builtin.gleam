import eyg/interpreter/cast
import eyg/interpreter/state
import eyg/interpreter/value as v
import gleam/dict
import gleam/int
import gleam/list
import gleam/order
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

pub const int_compare = state.Arity2(do_int_compare)

fn do_int_compare(left, right, _meta, env, k) {
  use left <- result.then(cast.as_integer(left))
  use right <- result.then(cast.as_integer(right))
  let return = case int.compare(left, right) {
    order.Lt -> v.Tagged("Lt", v.unit())
    order.Eq -> v.Tagged("Eq", v.unit())
    order.Gt -> v.Tagged("Gt", v.unit())
  }
  Ok(#(state.V(return), env, k))
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

pub const multiply = state.Arity2(do_multiply)

fn do_multiply(left, right, _meta, env, k) {
  use left <- try(cast.as_integer(left))
  use right <- try(cast.as_integer(right))
  Ok(#(state.V(v.Integer(left * right)), env, k))
}

pub const divide = state.Arity2(do_divide)

fn do_divide(left, right, _meta, env, k) {
  use left <- result.then(cast.as_integer(left))
  use right <- result.then(cast.as_integer(right))
  let value = case right {
    0 -> v.error(v.unit())
    _ -> v.ok(v.Integer(left / right))
  }
  Ok(#(state.V(value), env, k))
}

pub const absolute = state.Arity1(do_absolute)

fn do_absolute(x, _meta, env, k) {
  use x <- result.then(cast.as_integer(x))
  Ok(#(state.V(v.Integer(int.absolute_value(x))), env, k))
}

pub const int_parse = state.Arity1(do_int_parse)

fn do_int_parse(raw, _meta, env, k) {
  use raw <- result.then(cast.as_string(raw))
  let value = case int.parse(raw) {
    Ok(i) -> v.ok(v.Integer(i))
    Error(Nil) -> v.error(v.unit())
  }
  Ok(#(state.V(value), env, k))
}

pub const int_to_string = state.Arity1(do_int_to_string)

fn do_int_to_string(x, _meta, env, k) {
  use x <- result.then(cast.as_integer(x))
  Ok(#(state.V(v.String(int.to_string(x))), env, k))
}

pub const string_append = state.Arity2(do_string_append)

fn do_string_append(left, right, _meta, env, k) {
  use left <- try(cast.as_string(left))
  use right <- try(cast.as_string(right))
  Ok(#(state.V(v.String(string.append(left, right))), env, k))
}

pub const string_split = state.Arity2(do_string_split)

pub fn do_string_split(s, pattern, _meta, env, k) {
  use s <- result.then(cast.as_string(s))
  use pattern <- result.then(cast.as_string(pattern))
  let assert [first, ..parts] = string.split(s, pattern)
  let parts = v.LinkedList(list.map(parts, v.String))

  let value =
    v.Record(dict.from_list([#("head", v.String(first)), #("tail", parts)]))
  Ok(#(state.V(value), env, k))
}

pub const string_split_once = state.Arity2(do_string_split_once)

pub fn do_string_split_once(s, pattern, _meta, env, k) {
  use s <- result.then(cast.as_string(s))
  use pattern <- result.then(cast.as_string(pattern))
  let value = case string.split_once(s, pattern) {
    Ok(#(pre, post)) -> {
      let record =
        v.Record(
          dict.from_list([#("pre", v.String(pre)), #("post", v.String(post))]),
        )
      v.ok(record)
    }
    Error(Nil) -> v.error(v.unit())
  }
  Ok(#(state.V(value), env, k))
}

pub const string_uppercase = state.Arity1(do_string_uppercase)

pub fn do_string_uppercase(value, _meta, env, k) {
  use value <- result.then(cast.as_string(value))
  Ok(#(state.V(v.String(string.uppercase(value))), env, k))
}

pub const string_lowercase = state.Arity1(do_string_lowercase)

pub fn do_string_lowercase(value, _meta, env, k) {
  use value <- result.then(cast.as_string(value))
  Ok(#(state.V(v.String(string.lowercase(value))), env, k))
}

pub const string_starts_with = state.Arity2(do_string_starts_with)

pub fn do_string_starts_with(value, t, _meta, env, k) {
  use value <- result.then(cast.as_string(value))
  use t <- result.then(cast.as_string(t))

  Ok(#(state.V(bool(string.starts_with(value, t))), env, k))
}

pub const string_ends_with = state.Arity2(do_string_ends_with)

pub fn do_string_ends_with(value, t, _meta, env, k) {
  use value <- result.then(cast.as_string(value))
  use t <- result.then(cast.as_string(t))

  Ok(#(state.V(bool(string.ends_with(value, t))), env, k))
}

fn bool(value) {
  case value {
    True -> v.true()
    False -> v.false()
  }
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
