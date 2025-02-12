import eyg/analysis/typ as t
import eyg/runtime/cast
import eyg/runtime/interpreter/state
import eyg/runtime/value as v
import gleam/bit_array
import gleam/io
import gleam/list
import gleam/result
import gleam/string

pub fn append() {
  let type_ = t.Fun(t.Str, t.Open(0), t.Fun(t.Str, t.Open(1), t.Str))
  #(type_, state.Arity2(do_append))
}

pub fn do_append(left, right, rev, env, k) {
  use left <- result.then(cast.as_string(left))
  use right <- result.then(cast.as_string(right))
  Ok(#(state.V(v.String(string.append(left, right))), env, k))
}

pub fn split() {
  let type_ =
    t.Fun(t.Str, t.Open(0), t.Fun(t.Str, t.Open(1), t.LinkedList(t.Str)))
  #(type_, state.Arity2(do_split))
}

pub fn do_split(s, pattern, rev, env, k) {
  use s <- result.then(cast.as_string(s))
  use pattern <- result.then(cast.as_string(pattern))
  let assert [first, ..parts] = string.split(s, pattern)
  let parts = v.LinkedList(list.map(parts, v.String))

  Ok(#(
    state.V(v.Record([#("head", v.String(first)), #("tail", parts)])),
    env,
    k,
  ))
}

pub fn split_once() {
  let type_ =
    t.Fun(t.Str, t.Open(0), t.Fun(t.Str, t.Open(1), t.LinkedList(t.Str)))
  #(type_, state.Arity2(do_split_once))
}

pub fn do_split_once(s, pattern, rev, env, k) {
  use s <- result.then(cast.as_string(s))
  use pattern <- result.then(cast.as_string(pattern))
  let value = case string.split_once(s, pattern) {
    Ok(#(pre, post)) ->
      v.ok(v.Record([#("pre", v.String(pre)), #("post", v.String(post))]))
    Error(Nil) -> v.error(v.unit)
  }
  Ok(#(state.V(value), env, k))
}

pub fn uppercase() {
  let type_ = t.Fun(t.Str, t.Open(0), t.Str)
  #(type_, state.Arity1(do_uppercase))
}

pub fn do_uppercase(value, rev, env, k) {
  use value <- result.then(cast.as_string(value))
  Ok(#(state.V(v.String(string.uppercase(value))), env, k))
}

pub fn lowercase() {
  let type_ = t.Fun(t.Str, t.Open(0), t.Str)
  #(type_, state.Arity1(do_lowercase))
}

pub fn do_lowercase(value, rev, env, k) {
  use value <- result.then(cast.as_string(value))
  Ok(#(state.V(v.String(string.lowercase(value))), env, k))
}

pub fn starts_with() {
  let type_ =
    t.Fun(t.Str, t.Open(0), t.Fun(t.Str, t.Open(1), t.result(t.Str, t.unit)))
  #(type_, state.Arity2(do_starts_with))
}

pub fn do_starts_with(value, prefix, rev, env, k) {
  use value <- result.then(cast.as_string(value))
  use prefix <- result.then(cast.as_string(prefix))
  let ret = case string.split_once(value, prefix) {
    Ok(#("", post)) -> v.ok(v.String(post))
    _ -> v.error(v.unit)
  }
  Ok(#(state.V(ret), env, k))
}

pub fn ends_with() {
  let type_ =
    t.Fun(t.Str, t.Open(0), t.Fun(t.Str, t.Open(1), t.result(t.Str, t.unit)))
  #(type_, state.Arity2(do_ends_with))
}

pub fn do_ends_with(value, suffix, rev, env, k) {
  use value <- result.then(cast.as_string(value))
  use suffix <- result.then(cast.as_string(suffix))
  let ret = case string.split_once(value, suffix) {
    Ok(#(pre, "")) -> v.ok(v.String(pre))
    _ -> v.error(v.unit)
  }
  Ok(#(state.V(ret), env, k))
}

pub fn length() {
  let type_ = t.Fun(t.Str, t.Open(0), t.Integer)
  #(type_, state.Arity1(do_length))
}

pub fn do_length(value, rev, env, k) {
  use value <- result.then(cast.as_string(value))
  Ok(#(state.V(v.Integer(string.length(value))), env, k))
}

pub fn pop_grapheme() {
  let parts =
    t.Record(t.Extend("head", t.Str, t.Extend("tail", t.Str, t.Closed)))
  let type_ = t.Fun(t.Str, t.Open(1), t.result(parts, t.unit))
  #(type_, state.Arity1(do_pop_grapheme))
}

fn do_pop_grapheme(term, rev, env, k) {
  use string <- result.then(cast.as_string(term))
  let return = case string.pop_grapheme(string) {
    Error(Nil) -> v.error(v.unit)
    Ok(#(head, tail)) ->
      v.ok(v.Record([#("head", v.String(head)), #("tail", v.String(tail))]))
  }
  Ok(#(state.V(return), env, k))
}

pub fn replace() {
  let type_ =
    t.Fun(
      t.Str,
      t.Open(0),
      t.Fun(t.Str, t.Open(1), t.Fun(t.Str, t.Open(1), t.Str)),
    )
  #(type_, state.Arity3(do_replace))
}

pub fn do_replace(in, from, to, rev, env, k) {
  use in <- result.then(cast.as_string(in))
  use from <- result.then(cast.as_string(from))
  use to <- result.then(cast.as_string(to))

  Ok(#(state.V(v.String(string.replace(in, from, to))), env, k))
}

pub fn to_binary() {
  let type_ = t.Fun(t.Str, t.Open(0), t.Binary)
  #(type_, state.Arity1(do_to_binary))
}

pub fn do_to_binary(in, _meta, env, k) {
  use in <- result.then(cast.as_string(in))

  Ok(#(state.V(v.Binary(bit_array.from_string(in))), env, k))
}

pub fn from_binary() {
  let type_ = t.Fun(t.Binary, t.Open(0), t.result(t.Str, t.unit))
  #(type_, state.Arity1(do_from_binary))
}

pub fn do_from_binary(in, _meta, env, k) {
  use in <- result.then(cast.as_binary(in))
  let value = case bit_array.to_string(in) {
    Ok(bytes) -> v.ok(v.String(bytes))
    Error(Nil) -> v.error(v.unit)
  }
  Ok(#(state.V(value), env, k))
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
    _ -> state.call(no, v.unit, meta, env, k)
  }
}
