import eyg/interpreter/cast
import eyg/interpreter/state
import eyg/interpreter/value as v
import gleam/bit_array
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

pub const fix = state.Arity1(do_fix)

fn do_fix(builder, meta, env, k) {
  state.call(builder, v.Partial(v.Builtin("fixed"), [builder]), meta, env, k)
}

// fixed is not a builtin that is valid in expressions
// it is here so that a builder that only references it's self can be a value.
// technically its an arity 1 or 2 function.
pub const fixed = state.Arity2(do_fixed)

pub fn do_fixed(builder, arg, meta, env, k) {
  state.call(
    builder,
    v.Partial(v.Builtin("fixed"), [builder]),
    meta,
    env,
    state.Stack(state.CallWith(arg, env), meta, k),
  )
}

pub const int_compare = state.Arity2(do_int_compare)

fn do_int_compare(left, right, _meta, env, k) {
  use left <- try(cast.as_integer(left))
  use right <- try(cast.as_integer(right))
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
  use left <- try(cast.as_integer(left))
  use right <- try(cast.as_integer(right))
  let value = case right {
    0 -> v.error(v.unit())
    _ -> v.ok(v.Integer(left / right))
  }
  Ok(#(state.V(value), env, k))
}

pub const absolute = state.Arity1(do_absolute)

fn do_absolute(x, _meta, env, k) {
  use x <- try(cast.as_integer(x))
  Ok(#(state.V(v.Integer(int.absolute_value(x))), env, k))
}

pub const int_parse = state.Arity1(do_int_parse)

fn do_int_parse(raw, _meta, env, k) {
  use raw <- try(cast.as_string(raw))
  let value = case int.parse(raw) {
    Ok(i) -> v.ok(v.Integer(i))
    Error(Nil) -> v.error(v.unit())
  }
  Ok(#(state.V(value), env, k))
}

pub const int_to_string = state.Arity1(do_int_to_string)

fn do_int_to_string(x, _meta, env, k) {
  use x <- try(cast.as_integer(x))
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
  use s <- try(cast.as_string(s))
  use pattern <- try(cast.as_string(pattern))
  let assert [first, ..parts] = string.split(s, pattern)
  let parts = v.LinkedList(list.map(parts, v.String))

  let value =
    v.Record(dict.from_list([#("head", v.String(first)), #("tail", parts)]))
  Ok(#(state.V(value), env, k))
}

pub const string_split_once = state.Arity2(do_string_split_once)

pub fn do_string_split_once(s, pattern, _meta, env, k) {
  use s <- try(cast.as_string(s))
  use pattern <- try(cast.as_string(pattern))
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

pub const string_replace = state.Arity3(do_string_replace)

pub fn do_string_replace(in, from, to, _meta, env, k) {
  use in <- try(cast.as_string(in))
  use from <- try(cast.as_string(from))
  use to <- try(cast.as_string(to))

  Ok(#(state.V(v.String(string.replace(in, from, to))), env, k))
}

pub const string_uppercase = state.Arity1(do_string_uppercase)

pub fn do_string_uppercase(value, _meta, env, k) {
  use value <- try(cast.as_string(value))
  Ok(#(state.V(v.String(string.uppercase(value))), env, k))
}

pub const string_lowercase = state.Arity1(do_string_lowercase)

pub fn do_string_lowercase(value, _meta, env, k) {
  use value <- try(cast.as_string(value))
  Ok(#(state.V(v.String(string.lowercase(value))), env, k))
}

pub const string_starts_with = state.Arity2(do_string_starts_with)

pub fn do_string_starts_with(value, t, _meta, env, k) {
  use value <- try(cast.as_string(value))
  use t <- try(cast.as_string(t))

  Ok(#(state.V(bool(string.starts_with(value, t))), env, k))
}

pub const string_ends_with = state.Arity2(do_string_ends_with)

pub fn do_string_ends_with(value, t, _meta, env, k) {
  use value <- try(cast.as_string(value))
  use t <- try(cast.as_string(t))

  Ok(#(state.V(bool(string.ends_with(value, t))), env, k))
}

fn bool(value) {
  case value {
    True -> v.true()
    False -> v.false()
  }
}

pub const string_length = state.Arity1(do_string_length)

pub fn do_string_length(value, _meta, env, k) {
  use value <- try(cast.as_string(value))
  Ok(#(state.V(v.Integer(string.length(value))), env, k))
}

pub const string_to_binary = state.Arity1(do_string_to_binary)

pub fn do_string_to_binary(in, _meta, env, k) {
  use in <- try(cast.as_string(in))

  Ok(#(state.V(v.Binary(bit_array.from_string(in))), env, k))
}

pub const string_from_binary = state.Arity1(do_string_from_binary)

pub fn do_string_from_binary(in, _meta, env, k) {
  use in <- result.then(cast.as_binary(in))
  let value = case bit_array.to_string(in) {
    Ok(bytes) -> v.ok(v.String(bytes))
    Error(Nil) -> v.error(v.unit())
  }
  Ok(#(state.V(value), env, k))
}

pub const list_pop = state.Arity1(do_list_pop)

fn do_list_pop(term, _meta, env, k) {
  use elements <- result.then(cast.as_list(term))
  let return = case elements {
    [] -> v.error(v.unit())
    [head, ..tail] ->
      v.ok(
        v.Record(
          dict.from_list([#("head", head), #("tail", v.LinkedList(tail))]),
        ),
      )
  }
  Ok(#(state.V(return), env, k))
}

pub const list_fold = state.Arity3(do_list_fold)

fn do_list_fold(list, state, func, meta, env, k) {
  use elements <- try(cast.as_list(list))
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

pub const binary_from_integers = state.Arity1(do_binary_from_integers)

pub fn do_binary_from_integers(term, _meta, env, k) {
  use parts <- result.then(cast.as_list(term))
  let content =
    list.fold(list.reverse(parts), <<>>, fn(acc, el) {
      let assert v.Integer(i) = el
      <<i, acc:bits>>
    })
  Ok(#(state.V(v.Binary(content)), env, k))
}

pub const binary_fold = state.Arity3(do_binary_fold)

fn do_binary_fold(bytes, state, func, meta, env, k) {
  use bytes <- try(cast.as_binary(bytes))
  case bytes {
    <<>> -> Ok(#(state.V(state), env, k))
    <<byte, rest:bytes>> -> {
      state.call(
        func,
        v.Integer(byte),
        meta,
        env,
        state.Stack(
          state.CallWith(state, env),
          meta,
          state.Stack(
            state.Apply(
              v.Partial(v.Builtin("binary_fold"), [v.Binary(rest)]),
              env,
            ),
            meta,
            state.Stack(state.CallWith(func, env), meta, k),
          ),
        ),
      )
    }
    _ -> panic as "assume full bytes"
  }
}
