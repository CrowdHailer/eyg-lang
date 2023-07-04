import gleam/list
import gleam/string
import eyg/analysis/typ as t
import eyg/runtime/interpreter as r
import harness/ffi/cast

pub fn append() {
  let type_ = t.Fun(t.Binary, t.Open(0), t.Fun(t.Binary, t.Open(1), t.Binary))
  #(type_, r.Arity2(do_append))
}

pub fn do_append(left, right, _builtins, k) {
  use left <- cast.string(left)
  use right <- cast.string(right)
  r.continue(k, r.Binary(string.append(left, right)))
}

pub fn split() {
  let type_ =
    t.Fun(
      t.Binary,
      t.Open(0),
      t.Fun(t.Binary, t.Open(1), t.LinkedList(t.Binary)),
    )
  #(type_, r.Arity2(do_split))
}

pub fn do_split(s, pattern, _builtins, k) {
  use s <- cast.string(s)
  use pattern <- cast.string(pattern)
  let [first, ..parts] = string.split(s, pattern)
  let parts = r.LinkedList(list.map(parts, r.Binary))

  r.continue(k, r.Record([#("head", r.Binary(first)), #("tail", parts)]))
}

pub fn uppercase() {
  let type_ = t.Fun(t.Binary, t.Open(0), t.Binary)
  #(type_, r.Arity1(do_uppercase))
}

pub fn do_uppercase(value, _builtins, k) {
  use value <- cast.string(value)
  r.continue(k, r.Binary(string.uppercase(value)))
}

pub fn lowercase() {
  let type_ = t.Fun(t.Binary, t.Open(0), t.Binary)
  #(type_, r.Arity1(do_lowercase))
}

pub fn do_lowercase(value, _builtins, k) {
  use value <- cast.string(value)
  r.continue(k, r.Binary(string.lowercase(value)))
}

pub fn length() {
  let type_ = t.Fun(t.Binary, t.Open(0), t.Integer)
  #(type_, r.Arity1(do_length))
}

pub fn do_length(value, _builtins, k) {
  use value <- cast.string(value)
  r.continue(k, r.Integer(string.length(value)))
}

pub fn replace() {
  let type_ =
    t.Fun(
      t.Binary,
      t.Open(0),
      t.Fun(t.Binary, t.Open(1), t.Fun(t.Binary, t.Open(1), t.Binary)),
    )
  #(type_, r.Arity3(do_replace))
}

pub fn do_replace(in, from, to, _builtins, k) {
  use in <- cast.string(in)
  use from <- cast.string(from)
  use to <- cast.string(to)

  r.continue(k, r.Binary(string.replace(in, from, to)))
}
