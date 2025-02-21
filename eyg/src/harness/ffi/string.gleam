import eyg/analysis/typ as t
import eyg/interpreter/builtin
import eyg/interpreter/cast
import eyg/interpreter/state
import eyg/interpreter/value as v
import gleam/bit_array
import gleam/dict
import gleam/result
import gleam/string

pub fn append() {
  let type_ = t.Fun(t.Str, t.Open(0), t.Fun(t.Str, t.Open(1), t.Str))
  #(type_, builtin.string_append)
}

pub fn split() {
  let type_ =
    t.Fun(t.Str, t.Open(0), t.Fun(t.Str, t.Open(1), t.LinkedList(t.Str)))
  #(type_, builtin.string_split)
}

pub fn split_once() {
  let type_ =
    t.Fun(t.Str, t.Open(0), t.Fun(t.Str, t.Open(1), t.LinkedList(t.Str)))
  #(type_, builtin.string_split_once)
}

pub fn replace() {
  let type_ =
    t.Fun(
      t.Str,
      t.Open(0),
      t.Fun(t.Str, t.Open(1), t.Fun(t.Str, t.Open(1), t.Str)),
    )
  #(type_, builtin.string_replace)
}

pub fn uppercase() {
  let type_ = t.Fun(t.Str, t.Open(0), t.Str)
  #(type_, builtin.string_uppercase)
}

pub fn lowercase() {
  let type_ = t.Fun(t.Str, t.Open(0), t.Str)
  #(type_, builtin.string_lowercase)
}

pub fn starts_with() {
  let type_ =
    t.Fun(t.Str, t.Open(0), t.Fun(t.Str, t.Open(1), t.result(t.Str, t.unit)))
  #(
    type_,
    state.Arity1(fn(_, _, _, _) {
      panic as "implementation doesn't return result use pop prefix"
    }),
  )
}

pub fn ends_with() {
  let type_ =
    t.Fun(t.Str, t.Open(0), t.Fun(t.Str, t.Open(1), t.result(t.Str, t.unit)))
  #(
    type_,
    state.Arity1(fn(_, _, _, _) {
      panic as "implementation doesn't return result"
    }),
  )
}

pub fn length() {
  let type_ = t.Fun(t.Str, t.Open(0), t.Integer)
  #(type_, builtin.string_length)
}

pub fn pop_grapheme() {
  let parts =
    t.Record(t.Extend("head", t.Str, t.Extend("tail", t.Str, t.Closed)))
  let type_ = t.Fun(t.Str, t.Open(1), t.result(parts, t.unit))
  #(type_, state.Arity1(do_pop_grapheme))
}

fn do_pop_grapheme(term, _meta, env, k) {
  use string <- result.then(cast.as_string(term))
  let return = case string.pop_grapheme(string) {
    Error(Nil) -> v.error(v.unit())
    Ok(#(head, tail)) ->
      v.ok(
        v.Record(
          dict.from_list([#("head", v.String(head)), #("tail", v.String(tail))]),
        ),
      )
  }
  Ok(#(state.V(return), env, k))
}

pub fn to_binary() {
  let type_ = t.Fun(t.Str, t.Open(0), t.Binary)
  #(type_, builtin.string_to_binary)
}

pub fn from_binary() {
  let type_ = t.Fun(t.Binary, t.Open(0), t.result(t.Str, t.unit))
  #(type_, builtin.string_from_binary)
}

pub fn pop_prefix() {
  let type_ = t.Str
  #(type_, state.Arity4(do_pop_prefix))
}

pub fn do_pop_prefix(in, prefix, yes, no, meta, env, k) {
  use in <- result.then(cast.as_string(in))
  use prefix <- result.then(cast.as_string(prefix))

  case string.split_once(in, prefix) {
    Ok(#("", post)) -> state.call(yes, v.String(post), meta, env, k)
    _ -> state.call(no, v.unit(), meta, env, k)
  }
}
