import gleam/bit_array
import gleam/list
import gleam/string
import eyg/analysis/typ as t
import eyg/runtime/interpreter as r
import harness/ffi/cast

pub fn append() {
  let type_ = t.Fun(t.Str, t.Open(0), t.Fun(t.Str, t.Open(1), t.Str))
  #(type_, r.Arity2(do_append))
}

pub fn do_append(left, right, rev, env, k) {
  use left <- cast.require(cast.string(left), rev, env, k)
  use right <- cast.require(cast.string(right), rev, env, k)
  r.prim(r.Value(r.Str(string.append(left, right))), rev, env, k)
}

pub fn split() {
  let type_ =
    t.Fun(t.Str, t.Open(0), t.Fun(t.Str, t.Open(1), t.LinkedList(t.Str)))
  #(type_, r.Arity2(do_split))
}

pub fn do_split(s, pattern, rev, env, k) {
  use s <- cast.require(cast.string(s), rev, env, k)
  use pattern <- cast.require(cast.string(pattern), rev, env, k)
  let assert [first, ..parts] = string.split(s, pattern)
  let parts = r.LinkedList(list.map(parts, r.Str))

  r.prim(
    r.Value(r.Record([#("head", r.Str(first)), #("tail", parts)])),
    rev,
    env,
    k,
  )
}

pub fn split_once() {
  let type_ =
    t.Fun(t.Str, t.Open(0), t.Fun(t.Str, t.Open(1), t.LinkedList(t.Str)))
  #(type_, r.Arity2(do_split_once))
}

pub fn do_split_once(s, pattern, rev, env, k) {
  use s <- cast.require(cast.string(s), rev, env, k)
  use pattern <- cast.require(cast.string(pattern), rev, env, k)
  let value = case string.split_once(s, pattern) {
    Ok(#(pre, post)) ->
      r.ok(r.Record([#("pre", r.Str(pre)), #("post", r.Str(post))]))
    Error(Nil) -> r.error(r.unit)
  }
  r.prim(r.Value(value), rev, env, k)
}

pub fn uppercase() {
  let type_ = t.Fun(t.Str, t.Open(0), t.Str)
  #(type_, r.Arity1(do_uppercase))
}

pub fn do_uppercase(value, rev, env, k) {
  use value <- cast.require(cast.string(value), rev, env, k)
  r.prim(r.Value(r.Str(string.uppercase(value))), rev, env, k)
}

pub fn lowercase() {
  let type_ = t.Fun(t.Str, t.Open(0), t.Str)
  #(type_, r.Arity1(do_lowercase))
}

pub fn do_lowercase(value, rev, env, k) {
  use value <- cast.require(cast.string(value), rev, env, k)
  r.prim(r.Value(r.Str(string.lowercase(value))), rev, env, k)
}

pub fn starts_with() {
  let type_ =
    t.Fun(t.Str, t.Open(0), t.Fun(t.Str, t.Open(1), t.result(t.Str, t.unit)))
  #(type_, r.Arity2(do_starts_with))
}

pub fn do_starts_with(value, prefix, rev, env, k) {
  use value <- cast.require(cast.string(value), rev, env, k)
  use prefix <- cast.require(cast.string(prefix), rev, env, k)
  let ret = case string.split_once(value, prefix) {
    Ok(#("", post)) -> r.ok(r.Str(post))
    _ -> r.error(r.unit)
  }
  r.prim(r.Value(ret), rev, env, k)
}

pub fn ends_with() {
  let type_ =
    t.Fun(t.Str, t.Open(0), t.Fun(t.Str, t.Open(1), t.result(t.Str, t.unit)))
  #(type_, r.Arity2(do_ends_with))
}

pub fn do_ends_with(value, suffix, rev, env, k) {
  use value <- cast.require(cast.string(value), rev, env, k)
  use suffix <- cast.require(cast.string(suffix), rev, env, k)
  let ret = case string.split_once(value, suffix) {
    Ok(#(pre, "")) -> r.ok(r.Str(pre))
    _ -> r.error(r.unit)
  }
  r.prim(r.Value(ret), rev, env, k)
}

pub fn length() {
  let type_ = t.Fun(t.Str, t.Open(0), t.Integer)
  #(type_, r.Arity1(do_length))
}

pub fn do_length(value, rev, env, k) {
  use value <- cast.require(cast.string(value), rev, env, k)
  r.prim(r.Value(r.Integer(string.length(value))), rev, env, k)
}

pub fn pop_grapheme() {
  let parts =
    t.Record(t.Extend("head", t.Str, t.Extend("tail", t.Str, t.Closed)))
  let type_ = t.Fun(t.Str, t.Open(1), t.result(parts, t.unit))
  #(type_, r.Arity1(do_pop_grapheme))
}

fn do_pop_grapheme(term, rev, env, k) {
  use string <- cast.require(cast.string(term), rev, env, k)
  let return = case string.pop_grapheme(string) {
    Error(Nil) -> r.error(r.unit)
    Ok(#(head, tail)) ->
      r.ok(r.Record([#("head", r.Str(head)), #("tail", r.Str(tail))]))
  }
  r.prim(r.Value(return), rev, env, k)
}

pub fn replace() {
  let type_ =
    t.Fun(
      t.Str,
      t.Open(0),
      t.Fun(t.Str, t.Open(1), t.Fun(t.Str, t.Open(1), t.Str)),
    )
  #(type_, r.Arity3(do_replace))
}

pub fn do_replace(in, from, to, rev, env, k) {
  use in <- cast.require(cast.string(in), rev, env, k)
  use from <- cast.require(cast.string(from), rev, env, k)
  use to <- cast.require(cast.string(to), rev, env, k)

  r.prim(r.Value(r.Str(string.replace(in, from, to))), rev, env, k)
}

pub fn to_binary() {
  let type_ = t.Fun(t.Str, t.Open(0), t.Binary)
  #(type_, r.Arity1(do_to_binary))
}

pub fn do_to_binary(in, rev, env, k) {
  use in <- cast.require(cast.string(in), rev, env, k)

  r.prim(r.Value(r.Binary(bit_array.from_string(in))), rev, env, k)
}
